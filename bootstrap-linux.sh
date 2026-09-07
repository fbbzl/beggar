#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
mode=install
preview=0
components=()
for arg in "$@"; do
  case "$arg" in
    --dry-run) preview=1 ;;
    --check) [ "$mode" = install ] || { echo "模式参数不可重复或混用" >&2; exit 1; }; mode=check ;;
    --base-only) [ "$mode" = install ] || { echo "模式参数不可重复或混用" >&2; exit 1; }; mode=base_only ;;
    -h|--help)
      echo "用法: bash bootstrap-linux.sh [--check|--base-only] [--dry-run] [中间件选项]"
      echo "默认安装 Linux 基座并创建 3 节点 k3d 开发集群；不默认部署中间件。"
      echo "示例: bash bootstrap-linux.sh --base-only"
      echo "      bash bootstrap-linux.sh --minio"
      echo "支持 Ubuntu Desktop 24.04 / 带图形桌面的 Debian 13，x86_64 与 /dev/kvm。"
      exit 0 ;;
    *) components+=("$arg") ;;
  esac
done
if [ "$mode" = check ]; then
  [ "$preview" -eq 0 ] || { echo "--check 不与 --dry-run 混用" >&2; exit 1; }
  [ "${#components[@]}" -eq 0 ] || { echo "--check 仅检查基座，不接收中间件参数" >&2; exit 1; }
  exec bash "$SCRIPT_DIR/install-linux-base.sh" --check
fi
if [ "$mode" = base_only ]; then
  [ "${#components[@]}" -eq 0 ] || { echo "--base-only 不接收中间件参数" >&2; exit 1; }
fi
[ "$(id -u)" -ne 0 ] || { echo "请以普通桌面用户运行，脚本会在需要时自动使用 sudo。" >&2; exit 1; }
export PATH="/usr/local/bin:$PATH"
export PATH="$HOME/.rd/bin:/opt/rancher-desktop/bin:$PATH"
export DOCKER_HOST=unix:///var/run/docker.sock
unset DOCKER_CONTEXT DOCKER_TLS_VERIFY DOCKER_CERT_PATH
export KUBECONFIG="${BEGGAR_KUBECONFIG:-$HOME/.kube/${K3D_CLUSTER:-beggar-cluster}.yaml}"
# Validate selected components before any package or cluster mutation.
if [ "${#components[@]}" -gt 0 ]; then
  DRY_RUN=1 bash "$SCRIPT_DIR/deploy-registry-stack.sh" "${components[@]}" >/dev/null
fi
if [ "$preview" -eq 1 ]; then
  export DRY_RUN=1
  bash "$SCRIPT_DIR/install-linux-base.sh" --dry-run
else
  unset DRY_RUN
  bash "$SCRIPT_DIR/install-linux-base.sh"
fi
if [ "$mode" != base_only ]; then
  SKIP_REGISTRY=1 bash "$SCRIPT_DIR/deploy-k8s-cluster.sh" k3d
  if [ "${#components[@]}" -gt 0 ]; then
    bash "$SCRIPT_DIR/deploy-registry-stack.sh" "${components[@]}"
  fi
fi
if [ "$preview" -eq 1 ]; then
  echo "[DRY-RUN] 预览结束，未安装软件或创建集群。"
elif [ "$mode" = base_only ]; then
  echo "Linux 基座已就绪。"
else
  echo "Linux 基座和项目集群已就绪。"
  printf '查看节点: kubectl --kubeconfig %q get nodes -o wide\n' "$KUBECONFIG"
fi
