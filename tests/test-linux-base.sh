#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "$0")/.." && pwd)/install-linux-base.sh"

export BASE_SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/install-linux-base.sh"
passed=0
check_case() {
  local expected=$1 name=$2 script=$3 output status=0
  output=$(bash -eu -o pipefail -c "$script" 2>&1) || status=$?
  if [[ $expected == success && $status -ne 0 ]] || [[ $expected == failure && $status -eq 0 ]]; then
    printf 'FAIL: %s (status %s)\n%s\n' "$name" "$status" "$output" >&2
    exit 1
  fi
  printf 'PASS: %s\n' "$name"
  passed=$((passed + 1))
}

check_case success 'Ubuntu dry-run needs no dependencies or network' '
source "$BASE_SCRIPT"
uname() { [[ $1 == -s ]] && echo Linux || echo x86_64; }
base_os_release() { ID=ubuntu; VERSION_ID=24.04; VERSION_CODENAME=noble; }
base_systemd() { return 0; }
base_desktop_session() { return 0; }
base_kvm_access() { return 0; }
base_privileges() { exit 98; }
base_rancher_desktop_preflight() { exit 98; }
base_destination_preflight() { exit 98; }
base_download() { exit 98; }
apt-get() { exit 98; }
gpg() { exit 98; }
mktemp() { exit 98; }
base_main --dry-run
'
check_case success 'Debian x86_64 supported' '
source "$BASE_SCRIPT"
uname() { [[ $1 == -s ]] && echo Linux || echo x86_64; }
base_os_release() { ID=debian; VERSION_ID=13; VERSION_CODENAME=trixie; }
base_systemd() { return 0; }
base_desktop_session() { return 0; }
base_kvm_access() { return 0; }
base_platform
[[ $BASE_ARCH == amd64 ]]
'
check_case failure 'unsupported distribution' '
source "$BASE_SCRIPT"
uname() { echo Linux; }
base_os_release() { ID=ubuntu; VERSION_ID=22.04; VERSION_CODENAME=jammy; }
base_platform
'
check_case failure 'unsupported architecture' '
source "$BASE_SCRIPT"
uname() { [[ $1 == -s ]] && echo Linux || echo riscv64; }
base_os_release() { ID=debian; VERSION_ID=13; VERSION_CODENAME=trixie; }
base_platform
'
check_case failure 'systemd required' '
source "$BASE_SCRIPT"
uname() { [[ $1 == -s ]] && echo Linux || echo x86_64; }
base_os_release() { ID=debian; VERSION_ID=13; VERSION_CODENAME=trixie; }
base_systemd() { return 1; }
base_platform
'
check_case failure 'desktop session required' '
source "$BASE_SCRIPT"
base_desktop_session() { return 1; }
base_kvm_access() { return 0; }
base_runtime_preflight
'
check_case failure 'kvm access required' '
source "$BASE_SCRIPT"
base_desktop_session() { return 0; }
base_kvm_access() { return 1; }
base_runtime_preflight
'
check_case failure 'reject version injection' '
source "$BASE_SCRIPT"
K3D_VERSION="v5.9.0;uname"
base_versions
'
check_case failure 'reject unsupported k3d version' '
source "$BASE_SCRIPT"
K3D_VERSION=v6.0.0
base_versions
'
check_case success 'existing Rancher Desktop retained' '
source "$BASE_SCRIPT"
base_package_installed() { [[ $1 == rancher-desktop ]]; }
base_download() { exit 98; }
base_install_new() { exit 98; }
apt-get() { exit 98; }
base_install_rancher_desktop
'
check_case success 'Rancher Desktop repo install wires official source' '
source "$BASE_SCRIPT"
BASE_DOWNLOAD_DIR=/tmp/beggar-base-test
base_package_installed() { return 1; }
base_download() { printf "%s -> %s\n" "$1" "$2"; }
base_install_new() { printf "install %s %s %s\n" "$1" "$2" "$3"; }
apt-get() { printf "apt %s\n" "$*"; }
gpg() { :; }
output=$(base_install_rancher_desktop)
grep -q "https://download.opensuse.org/repositories/isv:/Rancher:/stable/deb/Release.key -> /tmp/beggar-base-test/rancher-desktop.asc" <<<"$output"
grep -q "install /tmp/beggar-base-test/isv-rancher-stable-archive-keyring.gpg /usr/share/keyrings/isv-rancher-stable-archive-keyring.gpg 0644" <<<"$output"
grep -q "install /tmp/beggar-base-test/isv-rancher-stable.list /etc/apt/sources.list.d/isv-rancher-stable.list 0644" <<<"$output"
grep -q "apt update" <<<"$output"
grep -q "apt install -y rancher-desktop" <<<"$output"
'
check_case success 'base main starts Rancher Desktop and installs k3d' '
source "$BASE_SCRIPT"
uname() { [[ $1 == -s ]] && echo Linux || echo x86_64; }
base_os_release() { ID=ubuntu; VERSION_ID=24.04; VERSION_CODENAME=noble; }
base_systemd() { return 0; }
base_desktop_session() { return 0; }
base_kvm_access() { return 0; }
base_rancher_desktop_preflight() { :; }
base_destination_preflight() { :; }
base_privileges() { :; }
base_wait_ready() { :; }
base_settings_ready() { return 0; }
base_package_installed() { return 1; }
base_install_rancher_desktop() { printf "install-rd\n"; }
base_install_cli() { printf "install-%s\n" "$1"; }
base_has() { case "$1" in docker|kubectl|helm|k3d|sudo|jq) return 0 ;; *) return 1 ;; esac; }
apt-get() { printf "apt %s\n" "$*"; }
rdctl() {
  case "$1" in
    start) printf "rdctl %s\n" "$*";;
    version) echo "v1.24.0";;
  esac
}
env() { [[ $* == "-u DOCKER_CONTEXT -u DOCKER_TLS_VERIFY -u DOCKER_CERT_PATH DOCKER_HOST=unix:///var/run/docker.sock timeout 60 docker info" ]]; }
kubectl() { [[ $* == "version --client" ]] && echo "Client Version: v1.35.5"; }
helm() { echo "v3.21.4"; }
k3d() { echo "v5.9.0"; }
base_verify() { :; }
output=$(HOME=/nonexistent-beggar-unit-home base_main)
grep -q -- '--application.admin-access=true' <<<"$output"
grep -q -- '--container-engine.name=moby' <<<"$output"
grep -q -- '--kubernetes.enabled=false' <<<"$output"
'
check_case success 'bootstrap base-only skips cluster and registry' '
source "$BASE_SCRIPT"
repo_root=$(cd "$(dirname "$BASE_SCRIPT")" && pwd)
real_bash=$(command -v bash)
stub_dir=$(mktemp -d)
log_file="$stub_dir/calls.log"
cat > "$stub_dir/bash" <<EOF
#!$real_bash
set -euo pipefail
case "\${1:-}" in
  -c|-lc) exec "$real_bash" "\$@" ;;
  *install-linux-base.sh)
    echo install >>"$log_file"
    exit 0 ;;
  *deploy-k8s-cluster.sh)
    echo cluster >>"$log_file"
    exit 99 ;;
  *deploy-registry-stack.sh)
    echo registry >>"$log_file"
    exit 99 ;;
  *)
    exec "$real_bash" "\$@" ;;
esac
EOF
chmod +x "$stub_dir/bash"
PATH="$stub_dir:$PATH" "$real_bash" "$repo_root/bootstrap-linux.sh" --base-only
grep -qx install "$log_file"
! grep -q cluster "$log_file"
! grep -q registry "$log_file"
'
check_case failure 'Rancher Desktop start is required' '
source "$BASE_SCRIPT"
base_has() { case "$1" in rdctl|docker|kubectl|helm|k3d) return 0 ;; *) return 1 ;; esac; }
env() { return 1; }
kubectl() { echo 'Client Version: v1.35.5'; }
helm() { echo 'v3.21.4'; }
k3d() { echo 'v5.9.0'; }
base_settings_ready() { return 0; }
base_verify
'
check_case failure 'malformed checksum' '
source "$BASE_SCRIPT"
base_hash_check /unused not-a-checksum
'
check_case failure 'checksum mismatch' '
source "$BASE_SCRIPT"
sha256sum() { printf "%064d  file\n" 0; }
base_hash_check /unused 1111111111111111111111111111111111111111111111111111111111111111
'
check_case success 'matching checksum' '
source "$BASE_SCRIPT"
sha256sum() { printf "%064d  file\n" 0; }
base_hash_check /unused 0000000000000000000000000000000000000000000000000000000000000000
'
check_case failure 'download failure propagates' '
source "$BASE_SCRIPT"
base_has() { return 1; }
BASE_DOWNLOAD_DIR=/unused
BASE_ARCH=amd64
base_download() { return 22; }
base_install_new() { exit 0; }
base_install_cli k3d
'
check_case success 'Rancher Desktop verification is local' '
source "$BASE_SCRIPT"
base_has() { return 0; }
env() { [[ $* == "-u DOCKER_CONTEXT -u DOCKER_TLS_VERIFY -u DOCKER_CERT_PATH DOCKER_HOST=unix:///var/run/docker.sock timeout 60 docker info" ]]; }
kubectl() { [[ $* == "version --client" ]]; }
helm() { echo v3.21.4; }
k3d() { echo v5.9.0; }
rdctl() { [[ $* == "version" ]] && echo 'v1.24.0'; }
base_settings_ready() { return 0; }
base_verify
'
check_case failure 'daemon failure' '
source "$BASE_SCRIPT"
base_has() { return 0; }
env() { return 1; }
base_settings_ready() { return 0; }
base_verify
'
check_case failure 'existing incompatible Helm' '
source "$BASE_SCRIPT"
base_has() { return 0; }
env() { return 0; }
kubectl() { return 0; }
helm() { echo v4.0.0; }
rdctl() { echo 'v1.24.0'; }
k3d() { echo 'v5.9.0'; }
base_settings_ready() { return 0; }
base_verify
'
check_case success 'published k3d checksum uses build path' '
source "$BASE_SCRIPT"
actual=$(printf "%s\n" "06d8f25bc3a971c4eb29e0ff08429b180402db0f4dec838c9eac427e296800a0  _dist/k3d-linux-amd64" | base_k3d_hash k3d-linux-amd64)
[[ $actual == 06d8f25bc3a971c4eb29e0ff08429b180402db0f4dec838c9eac427e296800a0 ]]
'
check_case success 'identical repository file reused after interruption' '
source "$BASE_SCRIPT"
fixture=$(mktemp -d)
printf repo > "$fixture/source"
cp "$fixture/source" "$fixture/destination"
base_install_new() { exit 98; }
base_install_repo_file "$fixture/source" "$fixture/destination"
'
check_case failure 'different repository file is never overwritten' '
source "$BASE_SCRIPT"
fixture=$(mktemp -d)
printf repo > "$fixture/source"
printf different > "$fixture/destination"
base_install_new() { exit 0; }
base_install_repo_file "$fixture/source" "$fixture/destination"
'
check_case success 'base-only preview never invokes cluster deployment' '
bootstrap="${BASE_SCRIPT%/*}/bootstrap-linux.sh"
bash() { [[ $1 == */install-linux-base.sh && $2 == --dry-run ]] || exit 98; }
id() { echo 1000; }
set -- --base-only --dry-run
source "$bootstrap"
'
printf '%s implementation unit cases passed.\n' "$passed"
