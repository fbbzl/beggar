#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "$0")/.." && pwd)
script="$repo_root/install-ecs-stack.sh"
passed=0

check_case() {
  local expected=$1 name=$2 code=$3 output status=0
  output=$(bash -eu -o pipefail -c "$code" 2>&1) || status=$?
  if [[ $expected == success && $status -ne 0 ]] || [[ $expected == failure && $status -eq 0 ]]; then
    printf 'FAIL: %s (status %s)\n%s\n' "$name" "$status" "$output" >&2
    exit 1
  fi
  printf 'PASS: %s\n' "$name"
  passed=$((passed + 1))
}

check_case success 'non-interactive cluster and mysql flow uses both scripts' '
script="'"$script"'"
real_bash=$(command -v bash)
stub_dir=$(mktemp -d)
log_file="$stub_dir/calls.log"
touch "$stub_dir/id_rsa"
cat > "$stub_dir/bash" <<EOF
#!$real_bash
set -euo pipefail
case "\${1:-}" in
  -c|-lc) exec "$real_bash" "\$@" ;;
  *deploy-k8s-cluster.sh)
    echo cluster >>"$log_file"
    printf "%s\n" "$*" >>"$log_file"
    exit 0 ;;
  *deploy-registry-stack.sh)
    echo registry >>"$log_file"
    printf "%s\n" "$*" >>"$log_file"
    exit 0 ;;
  *) exec "$real_bash" "\$@" ;;
esac
EOF
chmod +x "$stub_dir/bash"
PATH="$stub_dir:$PATH" \
INSTALL_TARGET=cluster-and-middleware \
NODE_IPS=10.0.0.11,10.0.0.12,10.0.0.13 \
SSH_USER=root \
SSH_KEY="$stub_dir/id_rsa" \
BEGGAR_KUBECONFIG="$stub_dir/config-beggar" \
DEPLOY_SELECTION=1 \
ASSUME_YES=1 \
DRY_RUN=1 \
"$real_bash" "$script" >/dev/null
grep -q cluster "$log_file"
grep -q registry "$log_file"
'

check_case success 'middleware-only can deploy platform-all' '
script="'"$script"'"
real_bash=$(command -v bash)
stub_dir=$(mktemp -d)
touch "$stub_dir/id_rsa"
cat > "$stub_dir/bash" <<EOF
#!$real_bash
set -euo pipefail
case "\${1:-}" in
  -c|-lc) exec "$real_bash" "\$@" ;;
  *deploy-k8s-cluster.sh)
    exit 99 ;;
  *deploy-registry-stack.sh)
    echo registry-called
    printf "%s\n" "\$*"
    exit 0 ;;
  *) exec "$real_bash" "\$@" ;;
esac
EOF
chmod +x "$stub_dir/bash"
output=$(PATH="$stub_dir:$PATH" \
INSTALL_TARGET=middleware-only \
DEPLOY_SELECTION=7 \
ASSUME_YES=1 \
DRY_RUN=1 \
BEGGAR_KUBECONFIG="$stub_dir/config-beggar" \
"$real_bash" "$script")
grep -q registry-called <<<"$output"
grep -q -- '--platform-all' <<<"$output"
'

check_case failure 'reject invalid ip' '
script="'"$script"'"
ASSUME_YES=1 \
INSTALL_TARGET=cluster-and-middleware \
NODE_IPS=10.0.0.1,10.0.0.2,999.0.0.3 \
SSH_USER=root \
SSH_KEY="$stub_dir/id_rsa" \
DEPLOY_SELECTION=1 \
DRY_RUN=1 \
bash "$script"
'

printf '%s implementation unit cases passed.\n' "$passed"
