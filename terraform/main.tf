# 최신 Ubuntu 이미지를 AWS에서 자동으로 찾아오는 코드
data "aws_ami" "ubuntu" {
  most_recent = true
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-*-*-amd64-server-*"]
  }
  owners = ["099720109477"] # Canonical (Ubuntu 공식 계정)
}

# ====================================================================================
# 1. Server 인스턴스 (Master Node + NAT + Bastion)
# ====================================================================================
resource "aws_instance" "k3s_server" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public.id     # Public Subnet에 위치 (공인 IP 가짐)
  key_name               = var.key_name
  vpc_security_group_ids = [aws_security_group.server_sg.id]
  
  # [중요] NAT Instance 역할을 하려면 소스/대상 확인을 꺼야 다른 애들의 패킷을 전달해줍니다.
  source_dest_check      = false

  # 인스턴스 시작 시 실행할 스크립트
  user_data = <<-EOF
              #!/bin/bash
              # 1. Swap 설정: t3.micro는 RAM이 1GB라 부족합니다. 하드 2GB를 RAM처럼 씁니다.
              fallocate -l 2G /swapfile && chmod 600 /swapfile && mkswap /swapfile && swapon /swapfile
              echo '/swapfile none swap sw 0 0' >> /etc/fstab

              # 2. NAT 설정: Agent들이 나를 통해 인터넷을 쓰도록 설정합니다.
              echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf && sysctl -p
              iptables -t nat -A POSTROUTING -o ens5 -j MASQUERADE || iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
              
              # 3. K3s Server 설치: Master 노드 역할을 시작합니다.
              curl -sfL https://get.k3s.io | K3S_TOKEN="${var.k3s_token}" sh -s - server \
                --node-ip $(curl -s http://169.254.169.254/latest/meta-data/local-ipv4) \
                --write-kubeconfig-mode 644
              EOF

  tags = { Name = "${var.project_name}-server" }
}

# ====================================================================================
# 2. Fixed Agent (고정형 모니터링 노드)
# 역할: Prometheus/Grafana 데이터를 저장하는 "절대 사라지지 않는" 노드입니다.
# ====================================================================================
resource "aws_instance" "k3s_agent_fixed" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.private.id # Private Subnet (보안 강화)
  key_name               = var.key_name
  vpc_security_group_ids = [aws_security_group.agent_sg.id]

  # Server가 먼저 켜져 있어야 Join 할 수 있으므로 순서를 지정합니다.
  depends_on = [aws_instance.k3s_server]

  user_data = <<-EOF
              #!/bin/bash
              # 1. Swap 설정 (필수)
              fallocate -l 2G /swapfile && chmod 600 /swapfile && mkswap /swapfile && swapon /swapfile
              echo '/swapfile none swap sw 0 0' >> /etc/fstab

              # 2. 라우팅 설정: 인터넷 트래픽을 Server(Master)로 보냅니다.
              SERVER_IP="${aws_instance.k3s_server.private_ip}"
              ip route add 192.168.1.0/24 dev eth0
              ip route replace default via $SERVER_IP dev eth0

              # 3. K3s Agent 설치
              # --node-label role=monitoring: "이 놈이 모니터링 노드다"라고 이름표를 붙입니다.
              until curl -sfL https://get.k3s.io | K3S_URL="https://$SERVER_IP:6443" \
                K3S_TOKEN="${var.k3s_token}" sh -s - agent --node-label role=monitoring; do
                sleep 10
              done
              EOF

  tags = { 
    Name = "${var.project_name}-agent-fixed"
  }
}

# ====================================================================================
# 3. Auto Scaling Group (확장형 워커 노드)
# 역할: 트래픽에 따라 자동으로 늘어나고 줄어드는 노드들입니다.
# ====================================================================================

# 3-1. 시작 템플릿 (인스턴스 붕어빵 틀)
resource "aws_launch_template" "k3s_agent_lt" {
  name_prefix   = "${var.project_name}-lt-"
  image_id      = data.aws_ami.ubuntu.id
  instance_type = var.instance_type
  key_name      = var.key_name
  vpc_security_group_ids = [aws_security_group.agent_sg.id]

  # User Data (Base64 인코딩 필수) - 위 Fixed Agent와 로직은 같으나 레이블이 다릅니다.
  user_data = base64encode(<<-EOF
              #!/bin/bash
              # 1. Swap 설정
              fallocate -l 2G /swapfile && chmod 600 /swapfile && mkswap /swapfile && swapon /swapfile
              echo '/swapfile none swap sw 0 0' >> /etc/fstab

              # 2. 라우팅 설정
              SERVER_IP="${aws_instance.k3s_server.private_ip}"
              ip route add 192.168.1.0/24 dev eth0
              ip route replace default via $SERVER_IP dev eth0

              # 3. K3s Agent 설치
              # --node-label role=worker: "나는 일반 일꾼이다"라고 이름표를 붙입니다.
              until curl -sfL https://get.k3s.io | K3S_URL="https://$SERVER_IP:6443" \
                K3S_TOKEN="${var.k3s_token}" sh -s - agent --node-label role=worker; do
                sleep 10
              done
              EOF
  )

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "${var.project_name}-agent-asg" # 생성되는 인스턴스 이름
    }
  }
}

# 3-2. 오토스케일링 그룹 (실제 인스턴스 관리자)
resource "aws_autoscaling_group" "k3s_agent_asg" {
  name                = "${var.project_name}-asg"
  vpc_zone_identifier = [aws_subnet.private.id] # Private Subnet에 생성
  
  min_size            = var.asg_min_size     # 최소 개수
  max_size            = var.asg_max_size     # 최대 개수
  desired_capacity    = var.asg_desired_capacity # 희망 개수

  launch_template {
    id      = aws_launch_template.k3s_agent_lt.id
    version = "$Latest"
  }

  health_check_grace_period = 300 # 5분간 헬스체크 유예 (부팅 시간 고려)
  health_check_type         = "EC2"

  tag {
    key                 = "Name"
    value               = "${var.project_name}-agent-asg-node"
    propagate_at_launch = true
  }
}
