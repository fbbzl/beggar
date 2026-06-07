#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="${NAMESPACE:-registry-stack}"
SKIP_REGISTRY="${SKIP_REGISTRY:-}"
DRY_RUN="${DRY_RUN:-}"

# Colors
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; GRAY='\033[0;90m'; NC='\033[0m'
step()  { echo -e "\n[$(date +%H:%M:%S)] >>> ${CYAN}$*${NC}"; }
info()  { echo -e "  ${GREEN}$*${NC}"; }
warn()  { echo -e "  ${YELLOW}[WARN] $*${NC}"; }
fatal() { echo -e "${RED}[FATAL] $*${NC}" >&2; exit 1; }
run() {
  if [ -n "$DRY_RUN" ]; then echo -e "  ${GRAY}[DRY-RUN] $*${NC}"; return 0; fi
  echo -e "  ${GRAY}> $*${NC}"
  eval "$@" 2>&1 || true
}

detect_os() {
  case "$(uname -s)" in
    Linux)  echo "linux" ;;
    Darwin) echo "macos" ;;
    *)      echo "unknown" ;;
  esac
}

require_cmd() {
  if ! command -v "$1" &>/dev/null; then
    fatal "需要 '$1'，请先安装。提示: $2"
  fi
}

# ────────────────────────────────
# 参数解析 (简单版，复杂场景用环境变量)
# ────────────────────────────────
MODE="${1:-}"
NODE_IPS="${NODE_IPS:-}"
SSH_USER="${SSH_USER:-root}"
SSH_KEY="${SSH_KEY:-$HOME/.ssh/id_rsa}"
K3S_VERSION="${K3S_VERSION:-v1.30.2+k3s2}"
K3D_NODES="${K3D_NODES:-3}"
K3D_CLUSTER="${K3D_CLUSTER:-beggar-cluster}"

step "环境检查"
OS=$(detect_os); info "平台: $OS"
require_cmd "kubectl" "https://kubernetes.io/docs/tasks/tools/"
require_cmd "helm"    "https://helm.sh/docs/intro/install/"

if [ -z "$SKIP_REGISTRY" ]; then
  SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
fi

# ────────────────────────────────
# 模式 A: k3d
# ────────────────────────────────
if [ "$MODE" = "k3d" ]; then
  step "k3d 模式: $K3D_CLUSTER ($K3D_NODES 节点)"
  require_cmd "docker" "https://docs.docker.com/engine/install/"
  if ! command -v k3d &>/dev/null; then
    warn "安装 k3d..."
    run "curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash"
  fi
  run "k3d cluster create $K3D_CLUSTER --servers 1 --agents $((K3D_NODES - 1)) --k3s-arg '--disable=traefik@server:0' --port '30000-30020:30000-30020@server:0' --wait"
  run "k3d kubeconfig merge $K3D_CLUSTER -d"

# ────────────────────────────────
# 模式 B: K3s 原生 HA
# ────────────────────────────────
elif [ "$MODE" = "k3s" ]; then
  [ -z "$NODE_IPS" ] && fatal "请设置 NODE_IPS 环境变量，逗号分隔，例如: NODE_IPS=10.0.0.1,10.0.0.2,10.0.0.3"
  IFS=',' read -ra IPS <<< "$NODE_IPS"
  [ ${#IPS[@]} -lt 3 ] && warn "HA 需要至少 3 节点，当前 ${#IPS[@]} 节点"

  require_cmd "ssh" "openssh-client"
  FIRST="${IPS[0]}"

  for node in "${IPS[@]}"; do
    step "检查节点: $node"
    ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=5 "$SSH_USER@$node" hostname 2>/dev/null || \
      fatal "无法连接 $node (ssh -i $SSH_KEY $SSH_USER@$node)"
    info "$node OK"
  done

  step "初始化第一个节点: $FIRST"
  run "ssh -i '$SSH_KEY' '$SSH_USER@$FIRST' 'curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION=$K3S_VERSION INSTALL_K3S_EXEC=\"--cluster-init --tls-san $FIRST --disable traefik --write-kubeconfig-mode 644\" sh -'"
  sleep 15

  TOKEN=$(ssh -i "$SSH_KEY" "$SSH_USER@$FIRST" 'sudo cat /var/lib/rancher/k3s/server/node-token' 2>/dev/null | tail -1)
  [ -z "$TOKEN" ] && fatal "无法获取节点 token"
  info "Token 获取成功"

  for node in "${IPS[@]:1}"; do
    step "加入节点: $node"
    run "ssh -i '$SSH_KEY' '$SSH_USER@$node' 'curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION=$K3S_VERSION INSTALL_K3S_EXEC=\"--server https://${FIRST}:6443 --token ${TOKEN} --disable traefik --write-kubeconfig-mode 644\" sh -'"
  done

  mkdir -p "$HOME/.kube"
  run "scp -i '$SSH_KEY' '$SSH_USER@$FIRST:/etc/rancher/k3s/k3s.yaml' '$HOME/.kube/config-beggar'"
  export KUBECONFIG="$HOME/.kube/config-beggar"
  info "kubeconfig: $HOME/.kube/config-beggar"
  info "使用: export KUBECONFIG=$HOME/.kube/config-beggar"

# ────────────────────────────────
# 模式 C: 仅检查 / 帮助
# ────────────────────────────────
else
  echo ""
  echo "Usage:"
  echo "  bash $0 k3d                  # 本地 k3d 集群 (需要 Docker)"
  echo "  bash $0 k3s                  # K3s HA 集群 (设置 NODE_IPS 环境变量)"
  echo ""
  echo "环境变量:"
  echo "  NODE_IPS=10.0.0.1,10.0.0.2,10.0.0.3"
  echo "  SSH_USER=root"
  echo "  K3S_VERSION=v1.30.2+k3s2"
  echo "  K3D_NODES=3"
  echo "  SKIP_REGISTRY=1          # 跳过中间件部署"
  echo "  DRY_RUN=1                # 仅校验"
  exit 0
fi

# ────────────────────────────────
# 验证集群
# ────────────────────────────────
step "验证集群"
kubectl cluster-info 2>/dev/null && kubectl get nodes -o wide || warn "集群尚未就绪"

# ────────────────────────────────
# 部署中间件
# ────────────────────────────────
if [ -z "$SKIP_REGISTRY" ] && [ -n "$SCRIPT_DIR" ]; then
  step "部署中间件..."
  args=()
  [ -n "$DRY_RUN" ] && args+=("--dry-run")
  bash "$SCRIPT_DIR/deploy-registry-stack.sh" "${args[@]}"
fi

step "全部完成"
