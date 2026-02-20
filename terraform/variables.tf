variable "aws_region" {
  description = "인프라가 배포될 AWS 리전"
  default     = "ap-northeast-2"
}

variable "project_name" {
  description = "리소스 Name 태그 접두사"
  default     = "k3s-project"
}

# [핵심 변경] t3.micro -> t3.medium (4GB RAM)
variable "instance_type" {
  description = "사용할 EC2 인스턴스 사양"
  default     = "t3.medium"
}

variable "key_name" {
  description = "EC2 접속에 사용할 Key Pair 이름"
  default     = "mykey"
}

variable "k3s_token" {
  description = "K3s 노드 연결용 비밀 토큰"
  default     = "k3s-token-2026-secret"
}

# [핵심 변경] ASG 최소 1대 유지 (Server + Fixed + ASG = 총 3대)
variable "asg_min_size" {
  description = "Auto Scaling Group 최소 크기"
  default     = 1
}

# [핵심 변경] 최대 3대까지 확장
variable "asg_max_size" {
  description = "Auto Scaling Group 최대 크기"
  default     = 3
}

# [핵심 변경] 초기 1대 자동 생성
variable "asg_desired_capacity" {
  description = "Auto Scaling Group 희망 크기"
  default     = 1
}
