# AWS 리전 설정 (기본값: 서울)
variable "region" { 
  description = "인프라가 배포될 AWS 리전"
  default     = "ap-northeast-2" 
}

# 프로젝트 이름 (리소스들의 이름표 접두사로 사용됨)
variable "project_name" { 
  description = "리소스 Name 태그 접두사"
  default     = "k3s-project" 
}

# [중요] EC2 인스턴스 타입 (t3.micro: 2vCPU, 1GB RAM)
# 프리티어 사용 가능. RAM이 적으므로 Swap 설정이 필수입니다.
variable "instance_type" { 
  description = "사용할 EC2 인스턴스 사양"
  default     = "t3.micro" 
}

# SSH 접속용 키 페어 이름 (AWS 콘솔에 미리 만들어둔 키 이름)
variable "key_name" { 
  description = "EC2 접속에 사용할 Key Pair 이름"
  default     = "mykey" 
}

# K3s 클러스터 조인 토큰 (Server와 Agent가 서로를 알아보고 합류하기 위한 암호)
variable "k3s_token" { 
  description = "K3s 노드 연결용 비밀 토큰"
  default     = "k3s-token-2026-secret" 
}

# [신규] ASG 최소 인스턴스 개수 (서버가 아무리 줄어도 이 밑으로는 안 내려감)
variable "asg_min_size" {
  description = "Auto Scaling Group 최소 크기"
  default     = 1
}

# [신규] ASG 최대 인스턴스 개수 (트래픽이 폭주해도 이 이상은 안 늘어남 - 요금 폭탄 방지)
variable "asg_max_size" {
  description = "Auto Scaling Group 최대 크기"
  default     = 3
}

# [신규] ASG 초기 희망 개수 (처음 배포할 때 생성될 워커 노드 개수)
variable "asg_desired_capacity" {
  description = "Auto Scaling Group 희망 크기"
  default     = 1
}
