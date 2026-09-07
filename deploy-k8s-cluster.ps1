#!/usr/bin/env pwsh
param(
    # === K3s 鍘熺敓妯″紡 (澶氬彴 Linux 鐗╃悊鏈?VM) ===
    [string[]]$NodeIps = @(),
    [string]$SshUser = "root",
    [string]$SshKeyPath = "",  # 榛樿 $HOME/.ssh/id_rsa
    [ValidateSet('yes','accept-new','no')][string]$StrictHostKeyChecking = 'accept-new',
    [string]$KnownHostsFile = "",
    [string]$K3sVersion = "v1.30.2+k3s2",

    # === k3d 妯″紡 (鏈湴 Docker 寮€鍙? ===
    [switch]$WithK3d,
    [int]$K3dNodeCount = 3,
    [string]$K3dClusterName = "beggar-cluster",

    # === 閫氱敤 ===
    [switch]$SkipRegistryStack,
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$HOME_DIR = if ($env:HOME) { $env:HOME } else { $env:USERPROFILE }

if (-not $SshKeyPath) { $SshKeyPath = "$HOME_DIR/.ssh/id_rsa" }
if (-not $KnownHostsFile) { $KnownHostsFile = "$HOME_DIR/.ssh/known_hosts" }

function Write-Step($msg) {
    Write-Host "`n[$(Get-Date -Format HH:mm:ss)] >>> $msg" -ForegroundColor Cyan
}

function Run($cmd) {
    if ($DryRun) { Write-Host "  [DRY-RUN] $cmd" -ForegroundColor DarkGray; return }
    Write-Host "  > $cmd" -ForegroundColor DarkGray
    Invoke-Expression $cmd 2>&1 | ForEach-Object { Write-Host "    $_" }
}
function RunSensitive($cmd) {
    if ($DryRun) { return }
    try { Invoke-Expression $cmd 2>&1 | ForEach-Object { Write-Host "    $_" } }
    catch { Write-Host "[FATAL] sensitive command failed" -ForegroundColor Red; exit 1 }
    if ($LASTEXITCODE -ne 0) { Write-Host "[FATAL] sensitive command failed" -ForegroundColor Red; exit 1 }
}

# 鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€
# 鍓嶇疆妫€鏌?# 鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€
Write-Step "检查环境"
if ($IsWindows -or $env:OS) {
    Write-Host "  骞冲彴: Windows" -ForegroundColor Green
} else {
    Write-Host "  骞冲彴: Linux / macOS" -ForegroundColor Green
}

$hasKubectl = Get-Command "kubectl" -ErrorAction SilentlyContinue
$hasHelm   = Get-Command "helm" -ErrorAction SilentlyContinue

# 鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€
# 妯″紡 A: k3d (鏈湴 Docker)
# 鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€
if ($WithK3d) {
    Write-Step "k3d 妯″紡: 鍒涘缓鏈湴 K3s 闆嗙兢 ($K3dClusterName, $K3dNodeCount 鑺傜偣)"

    if (!(Get-Command "k3d" -ErrorAction SilentlyContinue)) {
        Write-Host "[INFO] 瀹夎 k3d..." -ForegroundColor Yellow
        Run "curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash"
    }
    if (!(Get-Command "docker" -ErrorAction SilentlyContinue)) {
        Write-Host "[FATAL] 需要 Docker，请先安装" -ForegroundColor Red; exit 1
    }

    Run "k3d cluster create $K3dClusterName --servers 1 --agents $($K3dNodeCount - 1) --k3s-arg '--disable=traefik@server:0' --port '30000-30020:30000-30020@server:0' --wait"

    Run "k3d kubeconfig merge $K3dClusterName -d"
    Write-Host "  k3d 集群已就绪" -ForegroundColor Green
}

# 鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€
# 妯″紡 B: K3s 鍘熺敓 (澶氬彴 Linux)
# 鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€
elseif ($NodeIps.Count -ge 1) {
    Write-Step "K3s 鍘熺敓妯″紡: 澶氳妭鐐?HA (embedded etcd)"

    if ($DryRun) {
        Write-Host "  [DRY-RUN] 璺宠繃 SSH銆佽繙绋嬪畨瑁呫€乼oken 璇诲彇銆佺瓑寰呭拰 kubeconfig 涓嬭浇" -ForegroundColor DarkGray
        Write-Host "  [DRY-RUN] SSH 涓绘満瀵嗛挜绛栫暐: $StrictHostKeyChecking; known_hosts: $KnownHostsFile" -ForegroundColor DarkGray
    } else {

    if ($NodeIps.Count -lt 3) {
        Write-Host "[WARN] HA 闇€瑕佽嚦灏?3 鑺傜偣锛屽綋鍓?$($NodeIps.Count) 鑺傜偣" -ForegroundColor Yellow
    }

    # SSH 连通性检测
    foreach ($node in $NodeIps) {
        Write-Step "妫€鏌ヨ妭鐐? $node"
        $testCmd = "ssh -i $SshKeyPath -o StrictHostKeyChecking=$StrictHostKeyChecking -o UserKnownHostsFile=$KnownHostsFile -o ConnectTimeout=5 $SshUser@$node 'hostname' 2>/dev/null"
        $hostname = Invoke-Expression $testCmd
        if ($LASTEXITCODE -ne 0 -or !$hostname) {
            Write-Host "[FATAL] 鏃犳硶杩炴帴 $node, 璇锋鏌?" -ForegroundColor Red
            Write-Host "    ssh -i $SshKeyPath $SshUser@$node" -ForegroundColor Yellow
            exit 1
        }
        Write-Host "  $node -> $hostname" -ForegroundColor Green
    }

    $firstNode = $NodeIps[0]
    $otherNodes = @()
    if ($NodeIps.Count -gt 1) {
        $otherNodes = $NodeIps[1..($NodeIps.Count - 1)]
    }

    # 节点1: 初始化
    Write-Step "初始化第一个节点: $firstNode"
    $installOpts = "--cluster-init --tls-san $firstNode --disable traefik --write-kubeconfig-mode 644"
    Run "ssh -i $SshKeyPath $SshUser@$firstNode 'curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION=$K3sVersion INSTALL_K3S_EXEC=\"$installOpts\" sh -'"

    # 绛?k3s 灏辩华
    Start-Sleep 15

    # 鑾峰彇 token
    Write-Step "鑾峰彇鑺傜偣 Token"
    $tokenCmd = "ssh -i $SshKeyPath $SshUser@$firstNode 'sudo cat /var/lib/rancher/k3s/server/node-token' 2>/dev/null"
    $nodeToken = Invoke-Expression $tokenCmd | Select-Object -Last 1
    if (!$nodeToken) {
        Write-Host "[FATAL] 鏃犳硶鑾峰彇鑺傜偣 token" -ForegroundColor Red
        exit 1
    }
    Write-Host "  Token 鑾峰彇鎴愬姛" -ForegroundColor Green

    # 鍏朵綑鑺傜偣鍔犲叆
    foreach ($node in $otherNodes) {
        Write-Step "鍔犲叆鑺傜偣: $node"
        $joinOpts = "--server https://${firstNode}:6443 --token ${nodeToken} --disable traefik --write-kubeconfig-mode 644"
        RunSensitive "ssh -i $SshKeyPath -o StrictHostKeyChecking=$StrictHostKeyChecking -o UserKnownHostsFile=$KnownHostsFile $SshUser@$node 'curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION=$K3sVersion INSTALL_K3S_EXEC=\"$joinOpts\" sh -'"
    }

    # 鎷疯礉 kubeconfig
    Write-Step "閰嶇疆 kubectl"
    $kubeDir = "$HOME_DIR/.kube"
    New-Item -ItemType Directory -Force -Path $kubeDir | Out-Null
    Run "scp -i $SshKeyPath -o StrictHostKeyChecking=$StrictHostKeyChecking -o UserKnownHostsFile=$KnownHostsFile $SshUser@${firstNode}:/etc/rancher/k3s/k3s.yaml $kubeDir/config-beggar"
    $env:KUBECONFIG = "$kubeDir/config-beggar"
    Write-Host "  kubeconfig: $kubeDir/config-beggar" -ForegroundColor Green
    Write-Host "  浣跨敤: export KUBECONFIG=$kubeDir/config-beggar" -ForegroundColor Yellow
    }
}

# 鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€
# 妯″紡 C: 浠呮鏌ュ伐鍏烽摼
# 鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€
else {
    Write-Step "宸ュ叿閾炬鏌?(宸叉湁闆嗙兢妯″紡)"
    if (!$hasKubectl) { Write-Host "[INFO] 璇峰畨瑁?kubectl" -ForegroundColor Yellow }
    if (!$hasHelm)   { Write-Host "[INFO] 璇峰畨瑁?Helm" -ForegroundColor Yellow }
    if ($hasKubectl -and $hasHelm) {
        Write-Host "  工具链就绪" -ForegroundColor Green
    }
}

# 鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€
# 楠岃瘉闆嗙兢
# 鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€
if (Get-Command "kubectl" -ErrorAction SilentlyContinue) {
    Write-Step "楠岃瘉闆嗙兢"
    if (-not $DryRun) {
        kubectl cluster-info 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) {
            kubectl get nodes -o wide
        } else {
            Write-Host "[WARN] 闆嗙兢灏氭湭灏辩华" -ForegroundColor Yellow
        }
    }
}

# 鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€
# 璋冪敤涓棿浠堕儴缃?# 鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€
if (!$SkipRegistryStack) {
    Write-Step "閮ㄧ讲涓棿浠?.."
    $args = @()
    if ($DryRun) { $args += "-DryRun" }
    & "$ScriptDir/deploy-registry-stack.ps1" @args
}

Write-Step "鍏ㄩ儴瀹屾垚"
Write-Host ""
Write-Host "━━━ 集群信息 ━━━" -ForegroundColor Yellow
if ($WithK3d) {
    Write-Host "  闆嗙兢: $K3dClusterName (k3d)" -ForegroundColor Green
    Write-Host "  鐢ㄦ硶: k3d kubeconfig merge $K3dClusterName" -ForegroundColor Green
}
elseif ($NodeIps.Count -ge 1) {
    Write-Host "  鑺傜偣鏁? $($NodeIps.Count)" -ForegroundColor Green
    Write-Host "  API: https://${firstNode}:6443" -ForegroundColor Green
    Write-Host "  Kubeconfig: $HOME_DIR/.kube/config-beggar" -ForegroundColor Green
}
Write-Host "  鏌ョ湅: kubectl get nodes -o wide" -ForegroundColor Green
