#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
K3S_SCRIPT="$SCRIPT_DIR/deploy-k8s-cluster.sh"
REGISTRY_SCRIPT="$SCRIPT_DIR/deploy-registry-stack.sh"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; GRAY='\033[0;90m'; NC='\033[0m'

step()  { echo -e "\n[$(date +%H:%M:%S)] >>> ${CYAN}$*${NC}"; }
info()  { echo -e "  ${GREEN}$*${NC}"; }
warn()  { echo -e "  ${YELLOW}[WARN] $*${NC}"; }
fatal() { echo -e "${RED}[FATAL] $*${NC}" >&2; exit 1; }

trim() {
  local value=$1
  value="${value#${value%%[![:space:]]*}}"
  value="${value%${value##*[![:space:]]}}"
  printf '%s' "$value"
}

expand_home() {
  case $1 in
    '~') printf '%s' "$HOME" ;;
    '~/'*) printf '%s/%s' "$HOME" "${1#~/}" ;;
    *) printf '%s' "$1" ;;
  esac
}

prompt_value() {
  local __name=$1 prompt=$2 default=$3 value
  if [ -n "${!__name:-}" ]; then
    return 0
  fi
  if ! read -r -p "$prompt [$default]: " value; then
    value=""
  fi
  value="$(trim "${value:-}")"
  printf -v "$__name" '%s' "${value:-$default}"
}

prompt_choice() {
  local __name=$1 prompt=$2 default=$3 value
  if [ -n "${!__name:-}" ]; then
    return 0
  fi
  if ! read -r -p "$prompt [$default]: " value; then
    value=""
  fi
  value="$(trim "${value:-}")"
  printf -v "$__name" '%s' "${value:-$default}"
}

validate_ipv4() {
  local ip=$1 part
  [[ $ip =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || fatal "IP 格式不正确: $ip"
  IFS='.' read -r -a parts <<< "$ip"
  for part in "${parts[@]}"; do
    [[ $part =~ ^[0-9]+$ ]] || fatal "IP 格式不正确: $ip"
    (( part >= 0 && part <= 255 )) || fatal "IP 格式不正确: $ip"
  done
}

validate_ssh_user() {
  [[ $1 =~ ^[A-Za-z0-9][A-Za-z0-9_.-]{0,63}$ ]] || fatal "SSH 用户格式不正确"
}

validate_k3s_version() {
  [[ $1 =~ ^v[0-9]+\.[0-9]+\.[0-9]+\+k3s[0-9]+$ ]] || fatal "K3s 版本格式不正确，应类似 v1.30.2+k3s2"
}

validate_kubeconfig_path() {
  [[ $1 = /* && $1 != *:* ]] || fatal "kubeconfig 必须是单个绝对路径: $1"
}

append_flag() {
  local flag=$1 existing
  for existing in "${DEPLOY_FLAGS_LIST[@]:-}"; do
    [ "$existing" = "$flag" ] && return 0
  done
  DEPLOY_FLAGS_LIST+=("$flag")
}

append_flags() {
  local flag
  for flag in "$@"; do
    append_flag "$flag"
  done
}

normalize_flag() {
  case $1 in
    --sba|-sba|--spring-boot-admin) printf '%s' '--spring-boot-admin' ;;
    --mysql|--pg|--postgresql|--redis|--minio|--kafka|--es|--elasticsearch|--mongo|--mongodb|--zk|--zookeeper|--etcd|--nacos|--rocketmq|--sentinel|--skywalking|--apollo|--tdengine|--harbor|--shardingsphere|--apisix|--shenyu|--dubbo|--seata|--xxl-job|--prometheus|--pulsar|--flink|--jenkins|--openbao|--loki|--velero|--renovate|--cert-manager|--argocd|--kyverno|--all|--platform-all|--spring-boot-admin)
      printf '%s' "$1" ;;
    *) fatal "不支持的参数: $1" ;;
  esac
}

parse_custom_flags() {
  local raw=$1 token
  raw="${raw//,/ }"
  for token in $raw; do
    token="$(trim "$token")"
    [ -n "$token" ] || continue
    token="$(normalize_flag "$token")"
    append_flag "$token"
  done
}

selection_to_flags() {
  local selection=$1 token
  DEPLOY_FLAGS_LIST=()
  selection="${selection// /}"
  IFS=',' read -r -a tokens <<< "$selection"
  for token in "${tokens[@]}"; do
    token="$(trim "$token")"
    [ -n "$token" ] || continue
    case "$token" in
      1) append_flags --mysql --pg --redis --minio ;;
      2) append_flags --kafka --es --mongo --zk --etcd --rocketmq --pulsar --flink ;;
      3) append_flags --apollo --shardingsphere --xxl-job ;;
      4) append_flags --apisix --shenyu --dubbo --seata --sentinel --skywalking --harbor --prometheus --jenkins --spring-boot-admin ;;
      5) append_flags --cert-manager --argocd --kyverno --openbao --loki --velero --renovate ;;
      6) DEPLOY_FLAGS_LIST=(--all) ; return 0 ;;
      7) DEPLOY_FLAGS_LIST=(--platform-all) ; return 0 ;;
      8|custom) return 1 ;;
      *) fatal "未知部署选项: $token" ;;
    esac
  done
  [ ${#DEPLOY_FLAGS_LIST[@]} -gt 0 ] || return 1
}

show_menu() {
  cat <<'EOF'
部署范围：
  1) 数据库 / 基础存储（MySQL, PostgreSQL, Redis, MinIO；TDengine 暂不可自动部署）
  2) 消息 / 搜索 / 协调（Kafka, Elasticsearch, MongoDB, ZooKeeper, etcd, RocketMQ, Pulsar, Flink）
  3) 注册 / 配置 / 分库（Apollo, ShardingSphere, XXL-JOB；Nacos 暂不可自动部署）
  4) 网关 / 治理 / 监控（APISIX, ShenYu, Dubbo, Seata, Sentinel, SkyWalking, Harbor, Prometheus, Jenkins, Spring Boot Admin）
  5) 平台工具（cert-manager, Argo CD, Kyverno, OpenBao, Loki, Velero, Renovate）
  6) 全量（--all）
  7) 平台工具全量（--platform-all）
  8) 自定义 flags
EOF
}

usage() {
  cat <<EOF
用法: bash $0 [--dry-run] [--yes]

交互流程：
  1. 选择是否从空白 ECS 先组建 K3s 集群，还是仅部署已有集群上的中间件
  2. 如需建集群，输入 3 台 ECS 的 IP、SSH 用户、SSH 私钥和 kubeconfig 路径
  3. 选择要部署的中间件类别或自定义 flags
  4. 调用 $K3S_SCRIPT 与 $REGISTRY_SCRIPT 完成安装

可选环境变量：
  INSTALL_TARGET=cluster-and-middleware | middleware-only
  NODE_IPS=ip1,ip2,ip3
  SSH_USER=root
  SSH_KEY=~/.ssh/id_rsa
  BEGGAR_KUBECONFIG=~/.kube/config-beggar
  K3S_VERSION=v1.30.2+k3s2
  DEPLOY_SELECTION=1,4 | all | platform-all | custom
  DEPLOY_FLAGS="--mysql --redis"
  BEGGAR_VERSION_OVERRIDES="mysql=12.3.5,redis=27.0.13"
  ASSUME_YES=1
  VIEW_STATUS=y | n
  DRY_RUN=1

类别编号：
EOF
  show_menu
}

DRY_RUN="${DRY_RUN:-}"
ASSUME_YES="${ASSUME_YES:-}"
VIEW_STATUS="${VIEW_STATUS:-}"
BEGGAR_VERSION_OVERRIDES="${BEGGAR_VERSION_OVERRIDES:-}"
VERSION_MODE="${VERSION_MODE:-}"
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    --yes|-y) ASSUME_YES=1 ;;
    -h|--help) usage; exit 0 ;;
    *) fatal "未知参数: $arg" ;;
  esac
done

INSTALL_TARGET="${INSTALL_TARGET:-}"
SSH_USER="${SSH_USER:-root}"
SSH_KEY="$(expand_home "${SSH_KEY:-$HOME/.ssh/id_rsa}")"
KUBECONFIG_PATH="$(expand_home "${BEGGAR_KUBECONFIG:-$HOME/.kube/config-beggar}")"
K3S_VERSION="${K3S_VERSION:-v1.30.2+k3s2}"

if [ -z "$INSTALL_TARGET" ]; then
  prompt_choice INSTALL_TARGET "选择安装方式 (1=空白 ECS 组建 K3s + 部署中间件, 2=仅部署已有集群中的中间件)" "1"
fi

case "$INSTALL_TARGET" in
  1|cluster|cluster-and-middleware) INSTALL_TARGET="cluster-and-middleware" ;;
  2|middleware|middleware-only) INSTALL_TARGET="middleware-only" ;;
  *) fatal "未知安装方式: $INSTALL_TARGET" ;;
esac

if [ "$INSTALL_TARGET" = "cluster-and-middleware" ]; then
  prompt_value NODE_IPS "输入 3 台 ECS 的 IP（逗号分隔）" ""
  [ -n "$NODE_IPS" ] || fatal "必须输入 3 台 ECS 的 IP"
  NODE_IPS="$(trim "$NODE_IPS")"
  NODE_IPS="${NODE_IPS// /}"
  IFS=',' read -r -a NODE_IP_ARRAY <<< "$NODE_IPS"
  [ ${#NODE_IP_ARRAY[@]} -eq 3 ] || fatal "必须正好输入 3 个 IP"
  for ip in "${NODE_IP_ARRAY[@]}"; do
    validate_ipv4 "$ip"
  done
  [ "$(printf '%s\n' "${NODE_IP_ARRAY[@]}" | sort -u | wc -l)" -eq 3 ] || fatal "3 个 IP 不能重复"

  prompt_value SSH_USER "SSH 用户" "$SSH_USER"
  prompt_value SSH_KEY "SSH 私钥路径" "$SSH_KEY"
  prompt_value KUBECONFIG_PATH "kubeconfig 路径" "$KUBECONFIG_PATH"
  prompt_value K3S_VERSION "K3s 版本" "$K3S_VERSION"

  SSH_KEY="$(expand_home "$SSH_KEY")"
  KUBECONFIG_PATH="$(expand_home "$KUBECONFIG_PATH")"
  validate_ssh_user "$SSH_USER"
  validate_k3s_version "$K3S_VERSION"
  validate_kubeconfig_path "$KUBECONFIG_PATH"
  [ -f "$SSH_KEY" ] || fatal "SSH 私钥不存在: $SSH_KEY"
fi

if [ -z "${DEPLOY_SELECTION:-}" ]; then
  step "选择要部署的中间件"
  show_menu
  prompt_choice DEPLOY_SELECTION "请输入编号，可多选（例如 1,4,5；自定义选 8）" "1"
fi

DEPLOY_FLAGS_LIST=()
case "$DEPLOY_SELECTION" in
  all|--all|6)
    DEPLOY_FLAGS_LIST=(--all)
    ;;
  platform-all|--platform-all|7)
    DEPLOY_FLAGS_LIST=(--platform-all)
    ;;
  custom|8)
    prompt_value DEPLOY_FLAGS "输入 deploy-registry-stack.sh 的 flags（空格或逗号分隔）" "--mysql"
    parse_custom_flags "$DEPLOY_FLAGS"
    ;;
  *)
    selection_to_flags "$DEPLOY_SELECTION" || {
      prompt_value DEPLOY_FLAGS "输入 deploy-registry-stack.sh 的 flags（空格或逗号分隔）" "--mysql"
      parse_custom_flags "$DEPLOY_FLAGS"
    }
    ;;
esac

[ ${#DEPLOY_FLAGS_LIST[@]} -gt 0 ] || fatal "未选择任何部署项"

if [ -z "$BEGGAR_VERSION_OVERRIDES" ]; then
  if [ -n "$ASSUME_YES" ]; then
    VERSION_MODE=y
  elif [ -z "$VERSION_MODE" ]; then
    prompt_choice VERSION_MODE "是否使用默认版本？输入 y 使用默认版本，输入 n 指定版本" "y"
  fi
  case "$VERSION_MODE" in
    y|Y|yes|YES) BEGGAR_VERSION_OVERRIDES="" ;;
    n|N|no|NO)
      prompt_value BEGGAR_VERSION_OVERRIDES "输入版本覆盖（组件=版本；Helm 覆盖 Chart，原生清单覆盖镜像标签；逗号分隔）" ""
      ;;
    *) fatal "版本选择仅支持 y 或 n" ;;
  esac
fi

step "安装计划"
echo "  安装方式:        $INSTALL_TARGET"
echo "  K3s 脚本:        $K3S_SCRIPT"
echo "  中间件脚本:      $REGISTRY_SCRIPT"
echo "  kubeconfig:      $KUBECONFIG_PATH"
echo "  部署 flags:      ${DEPLOY_FLAGS_LIST[*]}"
echo "  版本策略:        $([ -n "$BEGGAR_VERSION_OVERRIDES" ] && echo "覆盖: $BEGGAR_VERSION_OVERRIDES" || echo "默认版本")"
echo "  dry-run:         ${DRY_RUN:-0}"

if [ "$INSTALL_TARGET" = "cluster-and-middleware" ]; then
  echo "  节点 IP:         $NODE_IPS"
  echo "  SSH 用户:        $SSH_USER"
  echo "  SSH 私钥:        $SSH_KEY"
  echo "  K3s 版本:        $K3S_VERSION"
fi

if [ -z "$ASSUME_YES" ]; then
  prompt_choice CONFIRM "确认开始执行? 输入 y 继续" "n"
  case "$CONFIRM" in
    y|Y|yes|YES) ;;
    *) fatal "已取消" ;;
  esac
fi

if [ "$INSTALL_TARGET" = "cluster-and-middleware" ]; then
  step "第 1 步: 组建 K3s 集群"
  if [ -n "$DRY_RUN" ]; then
    NODE_IPS="$NODE_IPS" SSH_USER="$SSH_USER" SSH_KEY="$SSH_KEY" K3S_VERSION="$K3S_VERSION" BEGGAR_KUBECONFIG="$KUBECONFIG_PATH" DRY_RUN=1 \
      bash "$K3S_SCRIPT" k3s
  else
    NODE_IPS="$NODE_IPS" SSH_USER="$SSH_USER" SSH_KEY="$SSH_KEY" K3S_VERSION="$K3S_VERSION" BEGGAR_KUBECONFIG="$KUBECONFIG_PATH" \
      bash "$K3S_SCRIPT" k3s
  fi
fi

step "第 2 步: 部署中间件"
if [ -n "$DRY_RUN" ]; then
  KUBECONFIG="$KUBECONFIG_PATH" BEGGAR_VERSION_OVERRIDES="$BEGGAR_VERSION_OVERRIDES" DRY_RUN=1 bash "$REGISTRY_SCRIPT" "${DEPLOY_FLAGS_LIST[@]}"
else
  KUBECONFIG="$KUBECONFIG_PATH" BEGGAR_VERSION_OVERRIDES="$BEGGAR_VERSION_OVERRIDES" bash "$REGISTRY_SCRIPT" "${DEPLOY_FLAGS_LIST[@]}"
fi

if [ -z "$DRY_RUN" ] && [ -z "$VIEW_STATUS" ] && [ -n "$ASSUME_YES" ]; then
  VIEW_STATUS=n
fi

if [ -z "$DRY_RUN" ]; then
  if [ -z "$VIEW_STATUS" ]; then
    prompt_choice VIEW_STATUS "是否立即查看节点状态？输入 y 查看" "n"
  fi

  case "$VIEW_STATUS" in
    y|Y|yes|YES)
      step "第 3 步: 查看集群状态"
      KUBECONFIG="$KUBECONFIG_PATH" kubectl get nodes -o wide
      KUBECONFIG="$KUBECONFIG_PATH" kubectl get pods -n registry-stack
      KUBECONFIG="$KUBECONFIG_PATH" kubectl get svc -n registry-stack
      ;;
    n|N|no|NO) ;;
    *) fatal "查看节点状态仅支持 y 或 n" ;;
  esac
fi

step "完成"
echo "  kubeconfig: $KUBECONFIG_PATH"
echo "  部署 flags: ${DEPLOY_FLAGS_LIST[*]}"
