terraform {
  backend "s3" {
    bucket = "seongho-tfstate-20260214"
    key    = "terraform.tfstate"
    region = "ap-northeast-2"
  }
}

data "aws_ami" "ubuntu" {
  most_recent = true
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-*-*-amd64-server-*"]
  }
  owners = ["099720109477"]
}

# 1. Server Instance
resource "aws_instance" "k3s_server" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public.id
  key_name               = var.key_name
  vpc_security_group_ids = [aws_security_group.server_sg.id]
  source_dest_check      = false

  user_data = <<-EOF
              #!/bin/bash
              # [Micro 잔재 삭제] Swap 생성 코드 제거됨 (Pure RAM 사용)
              
              # NAT 설정
              echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf && sysctl -p
              iptables -t nat -A POSTROUTING -o ens5 -j MASQUERADE || iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
              
              # K3s Server 설치
              curl -sfL https://get.k3s.io | K3S_TOKEN="${var.k3s_token}" sh -s - server \
                --node-ip $(curl -s http://169.254.169.254/latest/meta-data/local-ipv4) \
                --write-kubeconfig-mode 644
              EOF

  tags = { Name = "${var.project_name}-server" }
}

# 2. Fixed Agent Instance
resource "aws_instance" "k3s_agent_fixed" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.private.id
  key_name               = var.key_name
  vpc_security_group_ids = [aws_security_group.agent_sg.id]
  depends_on             = [aws_instance.k3s_server]

  user_data = <<-EOF
              #!/bin/bash
              # [Micro 잔재 삭제] Swap 생성 코드 제거됨

              # [필수 추가] IP 포워딩 활성화
              echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf && sysctl -p

              # 라우팅 설정
              SERVER_IP="${aws_instance.k3s_server.private_ip}"
              ip route add 192.168.1.0/24 dev eth0
              ip route replace default via $SERVER_IP dev eth0

              # K3s Agent 설치
              until curl -sfL https://get.k3s.io | K3S_URL="https://$SERVER_IP:6443" \
                K3S_TOKEN="${var.k3s_token}" sh -s - agent --node-label role=monitoring; do
                sleep 10
              done
              EOF

  tags = { Name = "${var.project_name}-agent-fixed" }
}

# 3. Auto Scaling Group
resource "aws_launch_template" "k3s_agent_lt" {
  name_prefix   = "${var.project_name}-lt-"
  image_id      = data.aws_ami.ubuntu.id
  instance_type = var.instance_type
  key_name      = var.key_name
  vpc_security_group_ids = [aws_security_group.agent_sg.id]

  user_data = base64encode(<<-EOF
              #!/bin/bash
              # [Micro 잔재 삭제] Swap 생성 코드 제거됨

              # [필수 추가] IP 포워딩 활성화 (ASG 노드 생존 필수)
              echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf && sysctl -p

              # 라우팅 설정
              SERVER_IP="${aws_instance.k3s_server.private_ip}"
              ip route add 192.168.1.0/24 dev eth0
              ip route replace default via $SERVER_IP dev eth0

              # K3s Agent 설치
              until curl -sfL https://get.k3s.io | K3S_URL="https://$SERVER_IP:6443" \
                K3S_TOKEN="${var.k3s_token}" sh -s - agent --node-label role=worker; do
                sleep 10
              done
              EOF
  )

  tag_specifications {
    resource_type = "instance"
    tags = { Name = "${var.project_name}-agent-asg" }
  }
}

resource "aws_autoscaling_group" "k3s_agent_asg" {
  count = var.asg_desired_capacity > 0 ? 1 : 0
  name                = "${var.project_name}-asg"
  vpc_zone_identifier = [aws_subnet.private.id]
  min_size            = var.asg_min_size
  max_size            = var.asg_max_size
  desired_capacity    = var.asg_desired_capacity

  launch_template {
    id      = aws_launch_template.k3s_agent_lt.id
    version = "$Latest"
  }
  health_check_grace_period = 300
  health_check_type         = "EC2"
  tag {
    key                 = "Name"
    value               = "${var.project_name}-agent-asg-node"
    propagate_at_launch = true
  }
}
