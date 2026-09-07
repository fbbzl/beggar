#!/usr/bin/env bash
set -euo pipefail

# Official sources: docs.rancherdesktop.io/getting-started/installation/,
# docs.rancherdesktop.io/references/rdctl-command-reference/,
# github.com/k3d-io/k3d/releases. This installer never removes existing software.
K3D_VERSION="${K3D_VERSION:-v5.9.0}"
BASE_MODE=install
BASE_SUDO=()

base_fatal() { printf '[ERROR] %s\n' "$*" >&2; exit 1; }
base_info() { printf '%s\n' "$*"; }
base_has() { command -v "$1" >/dev/null 2>&1; }
base_os_release() { source /etc/os-release; }
base_systemd() { [[ -d /run/systemd/system ]] && base_has systemctl; }
base_desktop_session() { [[ -n ${DISPLAY:-} || -n ${WAYLAND_DISPLAY:-} ]]; }
base_kvm_access() { [[ -r /dev/kvm && -w /dev/kvm ]]; }

base_args() {
  [[ $# -le 1 ]] || base_fatal '仅接受 --check 或 --dry-run。'
  case "${1:-}" in
    '') BASE_MODE=install ;;
    --check) BASE_MODE=check ;;
    --dry-run) BASE_MODE=dry-run ;;
    -h|--help)
      printf '%s\n' '用法: bash install-linux-base.sh [--check|--dry-run]' \
        '默认安装 Linux 桌面基座；支持 Ubuntu Desktop 24.04 / 带图形桌面的 Debian 13，x86_64。' \
        '需要图形桌面会话和 /dev/kvm 读写权限。版本覆盖: K3D_VERSION。已有工具不会覆盖。' \
        '--check 只检查；--dry-run 只输出计划，不联网、不写入。'
      exit 0 ;;
    *) base_fatal "未知选项: $1" ;;
  esac
}

base_platform() {
  [[ $(uname -s) == Linux ]] || base_fatal '只支持 Linux。'
  base_os_release
  case "${ID:-}:${VERSION_ID:-}:${VERSION_CODENAME:-}" in
    ubuntu:24.04:noble|debian:13:trixie) ;;
    *) base_fatal '仅支持 Ubuntu 24.04 noble / Debian 13 trixie。' ;;
  esac
  case "$(uname -m)" in
    x86_64) BASE_ARCH=amd64 ;;
    *) base_fatal 'Rancher Desktop Linux 仅支持 x86_64。' ;;
  esac
  base_systemd || base_fatal '需要使用 systemd 启动的 Linux 主机。'
  base_info "平台: $ID $VERSION_ID ($BASE_ARCH)"
}

base_versions() { [[ $K3D_VERSION =~ ^v5\.[0-9]+\.[0-9]+$ ]] || base_fatal 'K3D_VERSION 必须为 v5.x.y。'; }

base_plan() {
  base_info '[DRY-RUN] 检查 Rancher Desktop 发行版源、/dev/kvm、桌面会话和既有安装；保留已有软件，不卸载。'
  base_info '[DRY-RUN] 安装 Rancher Desktop 后，用 rdctl start --application.start-in-background --application.admin-access=true --application.path-management-strategy rcfiles --container-engine.name=moby --kubernetes.enabled=false 启动并配置它。'
  base_info '[DRY-RUN] Rancher Desktop 会提供 docker、kubectl、helm 和 nerdctl；脚本另外安装 k3d。'
  base_info "[DRY-RUN] 缺少 k3d 时下载 $K3D_VERSION，校验 SHA256 后安装到 /usr/local/bin。"
  base_info '[DRY-RUN] 不删除现有 Rancher Desktop 数据；失败时保留现场。'
}

base_runtime_preflight() {
  base_desktop_session || base_fatal 'Rancher Desktop 需要图形桌面会话，请在已登录的桌面终端里运行。'
  if ! base_kvm_access; then
    [[ $BASE_MODE == install && -c /dev/kvm ]] || base_fatal '缺少 /dev/kvm 读写权限；请确认硬件虚拟化已启用，且 KVM 驱动已加载。'
    base_privileges
    getent group kvm >/dev/null || base_fatal '系统没有 kvm 组，请检查 KVM 驱动安装。'
    base_info '为当前桌面用户配置 kvm 组权限。'
    "${BASE_SUDO[@]}" usermod -a -G kvm "$(id -un)"
    base_info 'KVM 权限已配置。请注销并重新登录桌面，然后重新执行同一安装命令；本次尚未完成基座安装。'
    exit 2
  fi
}

base_privileges() {
  [[ $EUID -ne 0 ]] || base_fatal '请以桌面用户运行，脚本会在需要时自动使用 sudo。'
  base_has sudo || base_fatal '安装需要 sudo；请先确保当前用户可以使用 sudo。'
  sudo -v || base_fatal '无法取得 sudo 权限。'
  BASE_SUDO=(sudo)
}

base_package_installed() {
  [[ $(dpkg-query -W -f='${db:Status-Status}' "$1" 2>/dev/null || true) == installed ]]
}

base_rancher_desktop_preflight() {
  base_package_installed rancher-desktop && return 0
  for file in /usr/share/keyrings/isv-rancher-stable-archive-keyring.gpg /etc/apt/sources.list.d/isv-rancher-stable.list; do
    [[ ! -L $file ]] || base_fatal "保留符号链接 $file；请核查后重试。"
    [[ ! -e $file || -f $file ]] || base_fatal "安装目标不是普通文件: $file"
  done
}

base_destination_preflight() {
  base_has k3d && return 0
  [[ ! -e /usr/local/bin/k3d && ! -L /usr/local/bin/k3d ]] || base_fatal '已有 /usr/local/bin/k3d，不覆盖。'
}

base_download() {
  curl --fail --show-error --silent --location --proto '=https' --tlsv1.2 \
    --connect-timeout 20 --max-time 600 --retry 2 --output "$2" "$1"
}

base_hash_check() {
  local file=$1 expected=$2 actual
  [[ $expected =~ ^[a-fA-F0-9]{64}$ ]] || base_fatal "无效 SHA256: $(basename "$file")"
  actual=$(sha256sum "$file")
  [[ ${actual%% *} == "${expected,,}" ]] || base_fatal "SHA256 不匹配: $(basename "$file")"
}

base_k3d_hash() {
  # v5.9.0 publishes build paths (_dist/); older releases use bare names.
  awk -v file="$1" '$2 == file || $2 == "_dist/" file { print $1 }'
}

base_install_new() {
  local source=$1 destination=$2 mode=$3
  # noclobber prevents replacing a file created concurrently after preflight.
  "${BASE_SUDO[@]}" bash -c 'set -eC; umask 077; cat -- "$1" > "$2"; chmod "$3" "$2"' \
    bash "$source" "$destination" "$mode"
}

base_install_repo_file() {
  local source=$1 destination=$2
  if [[ -e $destination || -L $destination ]]; then
    [[ -f $destination && ! -L $destination ]] && cmp -s -- "$source" "$destination" ||
      base_fatal "保留不同的已有源文件 $destination；请核查后重试。"
    base_info "复用已核对的源文件: $destination"
  else
    base_install_new "$source" "$destination" 0644
  fi
}

base_install_rancher_desktop() {
  if base_package_installed rancher-desktop; then
    base_info '保留已有 Rancher Desktop；不重装、不回滚。'
    return 0
  fi
  base_download 'https://download.opensuse.org/repositories/isv:/Rancher:/stable/deb/Release.key' \
    "$BASE_DOWNLOAD_DIR/rancher-desktop.asc"
  "${BASE_SUDO[@]}" install -d -m 0755 /usr/share/keyrings
  gpg --dearmor --yes --output "$BASE_DOWNLOAD_DIR/isv-rancher-stable-archive-keyring.gpg" \
    "$BASE_DOWNLOAD_DIR/rancher-desktop.asc"
  printf 'deb [signed-by=/usr/share/keyrings/isv-rancher-stable-archive-keyring.gpg] https://download.opensuse.org/repositories/isv:/Rancher:/stable/deb/ ./\n' \
    > "$BASE_DOWNLOAD_DIR/isv-rancher-stable.list"
  base_install_repo_file "$BASE_DOWNLOAD_DIR/isv-rancher-stable-archive-keyring.gpg" \
    /usr/share/keyrings/isv-rancher-stable-archive-keyring.gpg
  base_install_repo_file "$BASE_DOWNLOAD_DIR/isv-rancher-stable.list" \
    /etc/apt/sources.list.d/isv-rancher-stable.list
  "${BASE_SUDO[@]}" apt-get update
  "${BASE_SUDO[@]}" apt-get install -y rancher-desktop
}

base_install_cli() {
  local tool=$1 url file checksum binary
  [[ $tool == k3d ]] || base_fatal "不支持的工具: $tool"
  if base_has "$tool"; then base_info "保留已有 $tool: $(command -v "$tool")"; return 0; fi
  file="k3d-linux-$BASE_ARCH"
  url="https://github.com/k3d-io/k3d/releases/download/$K3D_VERSION"
  base_download "$url/$file" "$BASE_DOWNLOAD_DIR/$file"
  base_download "$url/checksums.txt" "$BASE_DOWNLOAD_DIR/$file.sha256"
  checksum=$(base_k3d_hash "$file" < "$BASE_DOWNLOAD_DIR/$file.sha256")
  base_hash_check "$BASE_DOWNLOAD_DIR/$file" "$checksum"
  "${BASE_SUDO[@]}" install -d -m 0755 /usr/local/bin
  base_install_new "$BASE_DOWNLOAD_DIR/$file" "/usr/local/bin/$tool" 0755
}

base_settings_ready() {
  timeout 10 rdctl list-settings 2>/dev/null | jq -e \
    '.containerEngine.name == "moby" and .kubernetes.enabled == false and .application.adminAccess == true' >/dev/null
}

base_wait_ready() {
  local deadline=$((SECONDS + 600))
  base_info '等待 Rancher Desktop 和本地 Docker 就绪（最多 10 分钟）……'
  while (( SECONDS < deadline )); do
    if base_settings_ready && env -u DOCKER_CONTEXT -u DOCKER_TLS_VERIFY -u DOCKER_CERT_PATH \
      DOCKER_HOST=unix:///var/run/docker.sock timeout 10 docker info >/dev/null 2>&1; then return 0; fi
    sleep 5
  done
  base_fatal 'Rancher Desktop 未在等待期内就绪。请查看桌面应用诊断，确认 Moby、管理员访问已开启且内置 Kubernetes 已关闭，再重跑。'
}

base_verify() {
  local version
  export PATH="$HOME/.rd/bin:/opt/rancher-desktop/bin:$PATH"
  for tool in rdctl docker kubectl helm k3d jq; do
    base_has "$tool" || base_fatal "缺少 $tool；请先运行安装入口。"
  done
  base_settings_ready || base_fatal 'Rancher Desktop 设置不兼容或服务不可用；需要 Moby、管理员访问，以及关闭内置 Kubernetes。已有设置未修改。'
  env -u DOCKER_CONTEXT -u DOCKER_TLS_VERIFY -u DOCKER_CERT_PATH \
    DOCKER_HOST=unix:///var/run/docker.sock timeout 60 docker info >/dev/null || \
    base_fatal 'Rancher Desktop 的本地 Docker 不可用；请先启动 RD 再重试。'
  rdctl version
  kubectl version --client
  version=$(helm version --short)
  [[ $version == v3.* ]] || base_fatal '现有 Helm 不是 3.x；请自行配置兼容版本，脚本不会覆盖。'
  base_info "Helm: $version"
  k3d version
  base_info 'Linux 基座检查通过；Rancher Desktop 已就绪并使用 Moby。'
}

base_main() {
  local existing_rd=0
  base_args "$@"
  base_versions
  base_platform
  if [[ $BASE_MODE == dry-run ]]; then base_plan; return 0; fi
  base_runtime_preflight
  if [[ $BASE_MODE == check ]]; then base_verify; return 0; fi
  base_rancher_desktop_preflight
  base_destination_preflight
  if [[ -e ${XDG_CONFIG_HOME:-$HOME/.config}/rancher-desktop/settings.json ||
        -L ${XDG_CONFIG_HOME:-$HOME/.config}/rancher-desktop/settings.json ]]; then existing_rd=1; fi
  base_privileges
  "${BASE_SUDO[@]}" apt-get update
  "${BASE_SUDO[@]}" apt-get install -y --no-remove ca-certificates curl gnupg jq
  BASE_DOWNLOAD_DIR=$(mktemp -d /tmp/beggar-base.XXXXXXXX)
  base_info "下载与诊断文件保留在 $BASE_DOWNLOAD_DIR；失败后不自动卸载或删除。"
  base_install_rancher_desktop
  base_install_cli k3d
  export PATH="$HOME/.rd/bin:/opt/rancher-desktop/bin:/usr/local/bin:$PATH"
  if [[ $existing_rd -eq 1 ]]; then
    base_info '保留已有 Rancher Desktop 设置；启动后检查兼容性。'
    rdctl start --no-modal-dialogs
  else
    rdctl start --application.start-in-background --application.admin-access=true --application.path-management-strategy rcfiles \
      --container-engine.name=moby --kubernetes.enabled=false --no-modal-dialogs
  fi
  base_wait_ready
  base_verify
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then base_main "$@"; fi
