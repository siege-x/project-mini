# ====================================================================================
# Server(Master) 노드용 보안 그룹
# ====================================================================================
resource "aws_security_group" "server_sg" {
  name        = "server-sg"
  description = "Security Group for K3s Server"
  vpc_id      = aws_vpc.main.id # 우리가 만든 VPC 안에 생성

  # 1. SSH 접속 허용 (22번 포트) - 관리자 접속용
  ingress { 
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] 
  }

  # 2. K3s API 서버 (6443번 포트) - 외부에서 kubectl 명령을 내릴 때 필요
  ingress { 
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  # 3. Nginx NodePort (30080번 포트) - 웹 서비스 접속용
  ingress { 
    from_port   = 30080
    to_port     = 30080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] 
    description = "Allow Nginx NodePort"
  }

  # [신규] 4. Grafana NodePort (30000번 포트) - 모니터링 대시보드 접속용 (필수!)
  ingress { 
    from_port   = 30000
    to_port     = 30000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] 
    description = "Allow Grafana NodePort"
  }

  # 5. 내부 통신 허용 (Private Subnet의 Agent들이 보내는 인터넷 요청 받기 - NAT 역할)
  ingress { 
    from_port   = 0
    to_port     = 0
    protocol    = "-1" # 모든 프로토콜 허용
    cidr_blocks = [aws_subnet.private.cidr_block]
  }

  # 6. 외부로 나가는 모든 트래픽 허용 (이게 없으면 인터넷 안 됨)
  egress { 
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# ====================================================================================
# Agent(Worker) 노드용 보안 그룹
# ====================================================================================
resource "aws_security_group" "agent_sg" {
  name        = "agent-sg"
  description = "Security Group for K3s Agents"
  vpc_id      = aws_vpc.main.id

  # 1. Server(Master)로부터 오는 명령 및 통신 허용
  ingress { 
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [aws_subnet.public.cidr_block]
  }
  
  # 2. Nginx 접속 허용 (30080)
  ingress { 
    from_port   = 30080
    to_port     = 30080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] 
  }

  # 3. Grafana 접속 허용 (30000) - 내부 통신용
  ingress { 
    from_port   = 30000
    to_port     = 30000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] 
  }

  # 4. 외부로 나가는 트래픽 허용 (Server를 통해 나감)
  egress { 
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
