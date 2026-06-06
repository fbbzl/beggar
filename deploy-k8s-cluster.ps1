#!/usr/bin/env pwsh
param(
    # === K3s 原生模式 (多台 Linux 物理机/VM) ===
    [string[]]$NodeIps = @(),
    [string]$SshUser = "root",
    [string]$SshKeyPath = "",  # 默认 $HOME/.ssh/id_rsa
    [string]$K3sVersion = "v1.30.2+k3s2",

    # === k3d 模式 (本地 Docker 开发) ===
    [switch]$WithK3d,
    [int]$K3dNodeCount = 3,
    [string]$K3dClusterName = "beggar-cluster",

    # === 通用 ===
    [switch]$SkipRegistryStack,
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$HOME_DIR = if ($env:HOME) { $env:HOME } else { $env:USERPROFILE }

if (-not $SshKeyPath) { $SshKeyPath = "$HOME_DIR/.ssh/id_rsa" }

function Write-Step($msg) {
    Write-Host "`n[$(Get-Date -Format HH:mm:ss)] >>> $msg" -ForegroundColor Cyan
}

function Run($cmd) {
    if ($DryRun) { Write-Host "  [DRY-RUN] $cmd" -ForegroundColor DarkGray; return }
    Write-Host "  > $cmd" -ForegroundColor DarkGray
    Invoke-Expression $cmd 2>&1 | ForEach-Object { Write-Host "    $_" }
}

# ──────────────────────────────────
# 前置检查
# ──────────────────────────────────
Write-Step "检查环境"
if ($IsWindows -or $env:OS) {
    Write-Host "  平台: Windows" -ForegroundColor Green
} else {
    Write-Host "  平台: Linux / macOS" -ForegroundColor Green
}

$hasKubectl = Get-Command "kubectl" -ErrorAction SilentlyContinue
$hasHelm   = Get-Command "helm" -ErrorAction SilentlyContinue

# ──────────────────────────────────
# 模式 A: k3d (本地 Docker)
# ──────────────────────────────────
if ($WithK3d) {
    Write-Step "k3d 模式: 创建本地 K3s 集群 ($K3dClusterName, $K3dNodeCount 节点)"

    if (!(Get-Command "k3d" -ErrorAction SilentlyContinue)) {
        Write-Host "[INFO] 安装 k3d..." -ForegroundColor Yellow
        Run "curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash"
    }
    if (!(Get-Command "docker" -ErrorAction SilentlyContinue)) {
        Write-Host "[FATAL] 需要 Docker，请先安装" -ForegroundColor Red; exit 1
    }

    Run "k3d cluster create $K3dClusterName --servers 1 --agents $($K3dNodeCount - 1) --k3s-arg '--disable=traefik@server:0' --port '30000-30020:30000-30020@server:0' --wait"

    Run "k3d kubeconfig merge $K3dClusterName -d"
    Write-Host "  k3d 集群已就绪" -ForegroundColor Green
}

# ──────────────────────────────────
# 模式 B: K3s 原生 (多台 Linux)
# ──────────────────────────────────
elseif ($NodeIps.Count -ge 1) {
    Write-Step "K3s 原生模式: 多节点 HA (embedded etcd)"

    if ($NodeIps.Count -lt 3) {
        Write-Host "[WARN] HA 需要至少 3 节点，当前 $($NodeIps.Count) 节点" -ForegroundColor Yellow
    }

    # SSH 连通性检测
    foreach ($node in $NodeIps) {
        Write-Step "检查节点: $node"
        $testCmd = "ssh -i $SshKeyPath -o StrictHostKeyChecking=no -o ConnectTimeout=5 $SshUser@$node 'hostname' 2>/dev/null"
        $hostname = Invoke-Expression $testCmd
        if ($LASTEXITCODE -ne 0 -or !$hostname) {
            Write-Host "[FATAL] 无法连接 $node, 请检查:" -ForegroundColor Red
            Write-Host "    ssh -i $SshKeyPath $SshUser@$node" -ForegroundColor Yellow
            exit 1
        }
        Write-Host "  $node -> $hostname" -ForegroundColor Green
    }

    $firstNode = $NodeIps[0]
    $otherNodes = $NodeIps[1..($NodeIps.Length-1)]

    # 节点1: 初始化
    Write-Step "初始化第一个节点: $firstNode"
    $installOpts = "--cluster-init --tls-san $firstNode --disable traefik --write-kubeconfig-mode 644"
    Run "ssh -i $SshKeyPath $SshUser@$firstNode 'curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION=$K3sVersion INSTALL_K3S_EXEC=\"$installOpts\" sh -'"

    # 等 k3s 就绪
    Start-Sleep 15

    # 获取 token
    Write-Step "获取节点 Token"
    $tokenCmd = "ssh -i $SshKeyPath $SshUser@$firstNode 'sudo cat /var/lib/rancher/k3s/server/node-token' 2>/dev/null"
    $nodeToken = Invoke-Expression $tokenCmd | Select-Object -Last 1
    if (!$nodeToken) {
        Write-Host "[FATAL] 无法获取节点 token" -ForegroundColor Red
        exit 1
    }
    Write-Host "  Token 获取成功" -ForegroundColor Green

    # 其余节点加入
    foreach ($node in $otherNodes) {
        Write-Step "加入节点: $node"
        $joinOpts = "--server https://${firstNode}:6443 --token ${nodeToken} --disable traefik --write-kubeconfig-mode 644"
        Run "ssh -i $SshKeyPath $SshUser@$node 'curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION=$K3sVersion INSTALL_K3S_EXEC=\"$joinOpts\" sh -'"
    }

    # 拷贝 kubeconfig
    Write-Step "配置 kubectl"
    $kubeDir = "$HOME_DIR/.kube"
    MkDir $kubeDir
    Run "scp -i $SshKeyPath $SshUser@${firstNode}:/etc/rancher/k3s/k3s.yaml $kubeDir/config-beggar"
    $env:KUBECONFIG = "$kubeDir/config-beggar"
    Write-Host "  kubeconfig: $kubeDir/config-beggar" -ForegroundColor Green
    Write-Host "  使用: export KUBECONFIG=$kubeDir/config-beggar" -ForegroundColor Yellow
}

# ──────────────────────────────────
# 模式 C: 仅检查工具链
# ──────────────────────────────────
else {
    Write-Step "工具链检查 (已有集群模式)"
    if (!$hasKubectl) { Write-Host "[INFO] 请安装 kubectl" -ForegroundColor Yellow }
    if (!$hasHelm)   { Write-Host "[INFO] 请安装 Helm" -ForegroundColor Yellow }
    if ($hasKubectl -and $hasHelm) {
        Write-Host "  工具链就绪" -ForegroundColor Green
    }
}

# ──────────────────────────────────
# 验证集群
# ──────────────────────────────────
if (Get-Command "kubectl" -ErrorAction SilentlyContinue) {
    Write-Step "验证集群"
    if (-not $DryRun) {
        kubectl cluster-info 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) {
            kubectl get nodes -o wide
        } else {
            Write-Host "[WARN] 集群尚未就绪" -ForegroundColor Yellow
        }
    }
}

# ──────────────────────────────────
# 调用中间件部署
# ──────────────────────────────────
if (!$SkipRegistryStack) {
    Write-Step "部署中间件..."
    $args = @()
    if ($DryRun) { $args += "-DryRun" }
    & "$ScriptDir/deploy-registry-stack.ps1" @args
}

Write-Step "全部完成"
Write-Host ""
Write-Host "━━━ 集群信息 ━━━" -ForegroundColor Yellow
if ($WithK3d) {
    Write-Host "  集群: $K3dClusterName (k3d)" -ForegroundColor Green
    Write-Host "  用法: k3d kubeconfig merge $K3dClusterName" -ForegroundColor Green
}
elseif ($NodeIps.Count -ge 1) {
    Write-Host "  节点数: $($NodeIps.Count)" -ForegroundColor Green
    Write-Host "  API: https://${firstNode}:6443" -ForegroundColor Green
    Write-Host "  Kubeconfig: $HOME_DIR/.kube/config-beggar" -ForegroundColor Green
}
Write-Host "  查看: kubectl get nodes -o wide" -ForegroundColor Green
