#!/bin/bash

# 인벤토리 파일 경로 변수 지정 (매번 치기 귀찮으니까요)
INVENTORY="inventory/hosts.yml"

echo "🔍 K3s Cluster Health Status"
echo "===================================="

# 1. 노드 연결 테스트
echo "1. Testing node connectivity via Ansible..."
# [-i inventory/hosts.yml] 옵션 추가됨
ansible all -i $INVENTORY -m ping -u ubuntu

# 2. 클러스터 노드 상태 확인 (K3s Server에서 실행)
echo "2. Checking K3s node status..."
# 그룹명이 [servers]인지 [masters]인지 hosts.yml 확인 필요 (일단 servers로 작성)
ansible servers -i $INVENTORY -m shell -a "kubectl get nodes -o wide" -u ubuntu

# 3. 모든 네임스페이스의 포드 상태 확인
echo "3. Checking system pods status..."
# [오타 수정] severs -> servers
ansible servers -i $INVENTORY -m shell -a "kubectl get pods -A" -u ubuntu

# 4. 서비스 가동 상태 확인 (K3s 맞춤형)
echo "4. Checking K3s service status on all nodes..."
echo "--- [Servers] ---"
ansible servers -i $INVENTORY -m shell -a "systemctl is-active k3s" -u ubuntu || echo "❌ K3s Server is not running"

echo "--- [Agents] ---"
ansible agents -i $INVENTORY -m shell -a "systemctl is-active k3s-agent" -u ubuntu || echo "❌ K3s Agent is not running"

# 5. K3s 리소스 사용량 확인
echo "5. Checking resource usage (CPU/Memory)..."
ansible servers -i $INVENTORY -m shell -a "kubectl top nodes" -u ubuntu || echo "⚠️ Metrics-server is starting up or not ready."

echo "✅ K3s Health Status check completed!"
