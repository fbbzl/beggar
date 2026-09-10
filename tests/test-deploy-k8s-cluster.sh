#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "$0")/.." && pwd)
script="$repo_root/deploy-k8s-cluster.sh"
real_bash=$(command -v bash)

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

test_k3s_uses_requested_kubeconfig() {
  local test_dir="$1" fake_bin="$test_dir/bin" log_file="$test_dir/calls.log"
  local key_file="$test_dir/key with spaces" kubeconfig="$test_dir/custom/config.yaml"
  mkdir -p "$fake_bin"
  touch "$key_file"

  cat > "$fake_bin/ssh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'ssh:' >>"$TEST_LOG"
printf '%q ' "$@" >>"$TEST_LOG"
printf '\n' >>"$TEST_LOG"
case "${*: -1}" in
  hostname) printf 'fake-node\n' ;;
  *node-token*) printf 'server-token\n' ;;
esac
EOF
  cat > "$fake_bin/scp" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'scp:' >>"$TEST_LOG"
printf '%q ' "$@" >>"$TEST_LOG"
printf '\n' >>"$TEST_LOG"
target=${!#}
printf 'server: https://127.0.0.1:6443\n' > "$target"
EOF
  cat > "$fake_bin/kubectl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'kubectl:%s\n' "$KUBECONFIG" >>"$TEST_LOG"
EOF
  chmod +x "$fake_bin/ssh" "$fake_bin/scp" "$fake_bin/kubectl"

  TEST_LOG="$log_file" PATH="$fake_bin:$PATH" HOME="$test_dir/home" \
    NODE_IPS=10.0.0.11,10.0.0.12,10.0.0.13 \
    SSH_USER=root SSH_KEY="$key_file" \
    BEGGAR_KUBECONFIG="$kubeconfig" \
    "$real_bash" "$script" k3s >/dev/null

  grep -Fxq 'server: https://10.0.0.11:6443' "$kubeconfig" || fail 'kubeconfig API 地址未替换为首节点 IP'
  [ "$(stat -c '%a' "$kubeconfig")" = 600 ] || fail 'kubeconfig 文件权限不是 600'
  grep -Fq "$(printf '%q' "$key_file")" "$log_file" || fail 'SSH 私钥路径中的空格未作为单个参数传递'
  [ "$(grep -Fxc "kubectl:$kubeconfig" "$log_file")" -eq 4 ] || fail 'kubectl 未使用指定 kubeconfig 完成验证'
}

test_k3s_rejects_duplicate_nodes() {
  local test_dir="$1" output status=0
  output=$(DRY_RUN=1 SKIP_REGISTRY=1 NODE_IPS=10.0.0.1,10.0.0.1,10.0.0.3 \
    "$real_bash" "$script" k3s 2>&1) || status=$?
  [ "$status" -ne 0 ] || fail '重复节点 IP 未被拒绝'
  grep -Fq '不能包含重复 IP' <<<"$output" || fail '重复节点 IP 的失败信息不明确'
}

test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT
test_k3s_uses_requested_kubeconfig "$test_dir"
test_k3s_rejects_duplicate_nodes "$test_dir"
printf 'PASS: K3s cluster bootstrap contracts\n'
