# Server(Master)의 공인 IP (Ansible이 SSH 접속할 주소)
output "server_public_ip" {
  description = "외부에서 접속 가능한 K3s Server(Bastion) IP"
  value       = aws_instance.k3s_server.public_ip
}

# [핵심] Fixed Agent(모니터링 노드)의 사설 IP
# Ansible 인벤토리에 이 IP만 넣어주면, 모니터링 도구가 여기에만 설치됩니다.
output "agent_fixed_private_ip" {
  description = "모니터링 노드(Fixed Agent)의 Private IP"
  value       = aws_instance.k3s_agent_fixed.private_ip
}
