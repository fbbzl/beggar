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
  eval "$@" 2>&1 || fatal "命令执行失败: $*"
}

run_args() {
  printf '  %s' "${DRY_RUN:+[DRY-RUN] }"
  printf '%q ' "$@"
  printf '\n'
  [ -n "$DRY_RUN" ] || "$@"
}

run_sensitive() {
  if [ -n "$DRY_RUN" ]; then return 0; fi
  eval "$1" 2>&1 || fatal "敏感命令执行失败"
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
[ $# -eq 0 ] || shift
NODE_IPS="${NODE_IPS:-}"
SSH_USER="${SSH_USER:-root}"
SSH_KEY="${SSH_KEY:-$HOME/.ssh/id_rsa}"
SSH_STRICT_HOST_KEY_CHECKING="${SSH_STRICT_HOST_KEY_CHECKING:-accept-new}"
SSH_KNOWN_HOSTS="${SSH_KNOWN_HOSTS:-$HOME/.ssh/known_hosts}"
K3S_VERSION="${K3S_VERSION:-v1.30.2+k3s2}"
K3D_NODES="${K3D_NODES:-3}"
K3D_CLUSTER="${K3D_CLUSTER:-beggar-cluster}"

step "环境检查"
OS=$(detect_os); info "平台: $OS"
if [ -z "$DRY_RUN" ] && [[ "$MODE" = k3d || "$MODE" = k3s ]]; then
  require_cmd "kubectl" "先运行 bash install-linux-base.sh"
  require_cmd "helm" "先运行 bash install-linux-base.sh"
fi

if [ -z "$SKIP_REGISTRY" ]; then
  SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
fi

# ────────────────────────────────
# 模式 A: k3d
# ────────────────────────────────
if [ "$MODE" = "k3d" ]; then
  step "k3d 模式: $K3D_CLUSTER ($K3D_NODES 节点)"
  [[ "$K3D_CLUSTER" =~ ^[a-z][a-z0-9-]{0,39}$ ]] || fatal "K3D_CLUSTER 必须为小写字母开头的字母、数字或连字符（最多40位）"
  [[ "$K3D_NODES" =~ ^[1-9][0-9]?$ ]] || fatal "K3D_NODES 必须为 1 到 99"
  K3D_IMAGE="${K3D_IMAGE:-rancher/k3s:v1.35.5-k3s1}"
  export KUBECONFIG="${BEGGAR_KUBECONFIG:-$HOME/.kube/$K3D_CLUSTER.yaml}"
  [[ "$KUBECONFIG" = /* && "$KUBECONFIG" != *:* ]] || fatal "BEGGAR_KUBECONFIG 必须为单个绝对路径"
  if [ -z "$DRY_RUN" ]; then
    require_cmd docker "先运行 bash install-linux-base.sh"
    require_cmd k3d "先运行 bash install-linux-base.sh"
    docker info >/dev/null || fatal "Docker 未就绪或当前用户无权访问"
    clusters=$(k3d cluster list --no-headers) || fatal "无法查询现有集群"
  else
    clusters=""
  fi
  if awk '{print $1}' <<<"$clusters" | grep -Fxq "$K3D_CLUSTER"; then
    info "复用已有集群 $K3D_CLUSTER；不重建、不更改拓扑"
  else
    run_args k3d cluster create "$K3D_CLUSTER" --servers 1 --agents "$((K3D_NODES - 1))" \
      --image "$K3D_IMAGE" --k3s-arg '--disable=traefik@server:0' \
      --port '127.0.0.1:30000-30020:30000-30020@server:0' --api-port '127.0.0.1:6445' \
      --kubeconfig-update-default=false --kubeconfig-switch-context=false --no-rollback --wait --timeout 180s
  fi
  if [ -n "$DRY_RUN" ]; then
    info "[DRY-RUN] 获取项目 kubeconfig: $KUBECONFIG（保留已有文件）"
  elif [ -e "$KUBECONFIG" ] || [ -L "$KUBECONFIG" ]; then
    [ -f "$KUBECONFIG" ] && [ ! -L "$KUBECONFIG" ] || fatal "kubeconfig 不是普通文件"
    info "保留已有 kubeconfig: $KUBECONFIG"
  else
    mkdir -p "$(dirname "$KUBECONFIG")"
    config=$(k3d kubeconfig get "$K3D_CLUSTER") || fatal "获取 kubeconfig 失败"
    [ -n "$config" ] || fatal "kubeconfig 为空"
    (umask 077; set -o noclobber; printf '%s\n' "$config" > "$KUBECONFIG")
    unset config
  fi
  if [ -z "$DRY_RUN" ]; then
    [ "$(kubectl config current-context)" = "k3d-$K3D_CLUSTER" ] || fatal "已有 kubeconfig 指向其他 context，请使用单独的 BEGGAR_KUBECONFIG"
    # A matching context name alone does not prove it targets this Docker cluster.
    expected_config=$(k3d kubeconfig get "$K3D_CLUSTER") || fatal "无法核对集群配置"
    expected_identity=$(kubectl --kubeconfig <(printf '%s\n' "$expected_config") config view --raw --minify -o 'jsonpath={.clusters[0].cluster.server}{"|"}{.clusters[0].cluster.certificate-authority-data}')
    actual_identity=$(kubectl config view --raw --minify -o 'jsonpath={.clusters[0].cluster.server}{"|"}{.clusters[0].cluster.certificate-authority-data}')
    [ -n "$expected_identity" ] && [ "$expected_identity" != '|' ] && [ "$actual_identity" = "$expected_identity" ] || fatal "已有 kubeconfig 与本地集群不匹配；请指定新的 BEGGAR_KUBECONFIG"
    unset expected_config expected_identity actual_identity
    run_args kubectl --context "k3d-$K3D_CLUSTER" cluster-info --request-timeout=10s
    run_args kubectl --context "k3d-$K3D_CLUSTER" wait --for=condition=Ready nodes --all --timeout=180s
    node_count=$(kubectl --context "k3d-$K3D_CLUSTER" get nodes -o name | wc -l)
    [ "$node_count" -eq "$K3D_NODES" ] || fatal "已有集群节点数与 K3D_NODES 不符；未修改集群"
  fi
  run_args kubectl --context "k3d-$K3D_CLUSTER" get nodes -o wide
  info "使用项目集群: export KUBECONFIG=$KUBECONFIG"

# ────────────────────────────────
# 模式 B: K3s 原生 HA
# ────────────────────────────────
elif [ "$MODE" = "k3s" ]; then
  [ -z "$NODE_IPS" ] && fatal "请设置 NODE_IPS 环境变量，逗号分隔，例如: NODE_IPS=10.0.0.1,10.0.0.2,10.0.0.3"
  IFS=',' read -ra IPS <<< "$NODE_IPS"
  [ ${#IPS[@]} -lt 3 ] && warn "HA 需要至少 3 节点，当前 ${#IPS[@]} 节点"
  FIRST="${IPS[0]}"

  if [ -n "$DRY_RUN" ]; then
    info "[DRY-RUN] 跳过 SSH 连通性、远程安装、token 读取、sleep 和 kubeconfig 下载"
    info "[DRY-RUN] 将在 $FIRST 初始化 K3s，并把其余节点加入集群（token 不写入日志）"
  else

  require_cmd "ssh" "openssh-client"

  for node in "${IPS[@]}"; do
    step "检查节点: $node"
    ssh -i "$SSH_KEY" -o StrictHostKeyChecking="$SSH_STRICT_HOST_KEY_CHECKING" -o UserKnownHostsFile="$SSH_KNOWN_HOSTS" -o ConnectTimeout=5 "$SSH_USER@$node" hostname 2>/dev/null || \
      fatal "无法连接 $node (ssh -i $SSH_KEY $SSH_USER@$node)"
    info "$node OK"
  done

  step "初始化第一个节点: $FIRST"
  run "ssh -i '$SSH_KEY' -o StrictHostKeyChecking='$SSH_STRICT_HOST_KEY_CHECKING' -o UserKnownHostsFile='$SSH_KNOWN_HOSTS' '$SSH_USER@$FIRST' 'curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION=$K3S_VERSION INSTALL_K3S_EXEC=\"--cluster-init --tls-san $FIRST --disable traefik --write-kubeconfig-mode 644\" sh -'"
  sleep 15

  TOKEN=$(ssh -i "$SSH_KEY" -o StrictHostKeyChecking="$SSH_STRICT_HOST_KEY_CHECKING" -o UserKnownHostsFile="$SSH_KNOWN_HOSTS" "$SSH_USER@$FIRST" 'sudo cat /var/lib/rancher/k3s/server/node-token' 2>/dev/null | tail -1)
  [ -z "$TOKEN" ] && fatal "无法获取节点 token"
  info "Token 获取成功"

  for node in "${IPS[@]:1}"; do
    step "加入节点: $node"
    run_sensitive "ssh -i '$SSH_KEY' -o StrictHostKeyChecking='$SSH_STRICT_HOST_KEY_CHECKING' -o UserKnownHostsFile='$SSH_KNOWN_HOSTS' '$SSH_USER@$node' 'curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION=$K3S_VERSION INSTALL_K3S_EXEC=\"--server https://${FIRST}:6443 --token ${TOKEN} --disable traefik --write-kubeconfig-mode 644\" sh -'"
  done

  mkdir -p "$HOME/.kube"
  run "scp -i '$SSH_KEY' -o StrictHostKeyChecking='$SSH_STRICT_HOST_KEY_CHECKING' -o UserKnownHostsFile='$SSH_KNOWN_HOSTS' '$SSH_USER@$FIRST:/etc/rancher/k3s/k3s.yaml' '$HOME/.kube/config-beggar'"
  export KUBECONFIG="$HOME/.kube/config-beggar"
  kubectl cluster-info || fatal "K3s 控制面尚未就绪"
  kubectl wait --for=condition=Ready nodes --all --timeout=180s || fatal "K3s 节点尚未全部 Ready"
  info "kubeconfig: $HOME/.kube/config-beggar"
  info "使用: export KUBECONFIG=$HOME/.kube/config-beggar"
  fi

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
if [ "$MODE" != k3d ] && [ -z "$DRY_RUN" ]; then
  kubectl cluster-info && kubectl get nodes -o wide || fatal "集群尚未就绪"
fi

# ────────────────────────────────
# 部署中间件
# ────────────────────────────────
if [ -z "$SKIP_REGISTRY" ] && [ $# -gt 0 ]; then
  step "部署中间件..."
  args=()
  [ -n "$DRY_RUN" ] && args+=("--dry-run")
  bash "$SCRIPT_DIR/deploy-registry-stack.sh" "${args[@]}" "$@"
fi

step "全部完成"
