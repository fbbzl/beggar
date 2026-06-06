param(
    [string]$Namespace = "registry-stack",
    [string]$AdminPassword = "Harbor12345",

    # === 部署模式 ===
    [switch]$WithIngress,
    [string]$IngressDomain = "registry.local",

    # === 中间件开关 ===
    [switch]$WithKafka,
    [switch]$WithElasticsearch,
    [switch]$WithNacos,
    [switch]$WithRocketMQ,
    [switch]$WithSentinel,
    [switch]$WithSkyWalking,
    [switch]$WithMongoDB,
    [switch]$WithZooKeeper,
    [switch]$WithApollo,
    [switch]$WithTDengine,
    [switch]$WithMinIO,

    # === 快捷 ===
    [switch]$WithAll,
    [switch]$DryRun
)

if ($WithAll) {
    $WithKafka = $WithElasticsearch = $WithNacos = $WithRocketMQ = $true
    $WithSentinel = $WithSkyWalking = $WithMongoDB = $WithZooKeeper = $true
    $WithApollo = $WithTDengine = $WithMinIO = $true
}

# ── globals ──
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Info = [System.Collections.ArrayList]@()
$DeployedOk = $true
$crossSep = if ($IsWindows -or $env:OS) { '\' } else { '/' }

function Write-Step($msg) {
    Write-Host "`n[$(Get-Date -Format HH:mm:ss)] >>> $msg" -ForegroundColor Cyan
}

function Check-Cmd($cmd) {
    if (!(Get-Command $cmd -ErrorAction SilentlyContinue)) {
        Write-Host "[FATAL] 未找到命令 '$cmd'，请先安装" -ForegroundColor Red
        if ($cmd -eq "pwsh") { Write-Host "  提示: Linux 下运行 'curl -fsSL https://aka.ms/install-powershell | bash' 安装 pwsh" -ForegroundColor Yellow }
        exit 1
    }
}

function Helms($name) {
    # helm search repo -l | grep name 检查 chart 是否存在
    $r = helm search repo $name --fail-on-no-result 2>&1 | Select-String "^$name\s"
    return [bool]$r
}

function Hlm($name, $chart, $values, $extra) {
    if ($DryRun) {
        Write-Host "  [DRY-RUN] helm upgrade --install $name $chart --namespace $Namespace [values]" -ForegroundColor DarkGray
        return
    }
    $argsList = @("upgrade", "--install", $name, $chart,
        "--namespace", $Namespace, "--wait", "--timeout", "10m")
    if ($values) { $argsList += "--values", (Resolve-Path $values) }
    if ($extra)  { $argsList += $extra }
    try {
        $output = helm $argsList *>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Host "  [WARN] $name 部署异常:" -ForegroundColor Yellow
            $output | ForEach-Object { Write-Host "    $_" -ForegroundColor DarkGray }
            return $false
        }
        Write-Host "  $name 部署完成" -ForegroundColor Green
        return $true
    } catch {
        Write-Host "  [WARN] $name 异常: $_" -ForegroundColor Yellow
        return $false
    }
}

function KubeApply($file) {
    if ($DryRun) {
        Write-Host "  [DRY-RUN] kubectl apply -n $Namespace -f $(Split-Path $file -Leaf)" -ForegroundColor DarkGray
        return
    }
    $output = kubectl apply -n $Namespace -f (Resolve-Path $file) 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  [WARN] $(Split-Path $file -Leaf) 部署异常:" -ForegroundColor Yellow
        $output | ForEach-Object { Write-Host "    $_" -ForegroundColor DarkGray }
    } else {
        Write-Host "  $(Split-Path $file -Leaf) 部署完成" -ForegroundColor Green
    }
}

function ExecInPod($podSelector, $cmd) {
    $pod = kubectl get pod -n $Namespace -l $podSelector -o jsonpath='{.items[0].metadata.name}' 2>$null
    if (-not $pod) { return $false }
    $output = kubectl exec -n $Namespace $pod -- bash -c $cmd 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  [WARN] exec 失败: $cmd" -ForegroundColor Yellow
        $output | ForEach-Object { Write-Host "    $_" -ForegroundColor DarkGray }
        return $false
    }
    return $true
}

function MkDir($p) {
    if (!(Test-Path $p)) { New-Item -ItemType Directory -Path $p -Force | Out-Null }
}

# ==========================================================================
# 0. PRECHECK
# ==========================================================================
Write-Step "前提条件检查"
Check-Cmd "helm"; Check-Cmd "kubectl"
$pwshVer = $PSVersionTable.PSVersion
Write-Host "  PowerShell: $($pwshVer.Major).$($pwshVer.Minor)" -ForegroundColor Green
Write-Host "  Helm: $(helm version --short 2>&1)" -ForegroundColor Green

if (-not $DryRun) {
    kubectl cluster-info --request-timeout 5s 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[FATAL] 无法连接 K8s 集群，请检查 kubeconfig" -ForegroundColor Red
        exit 1
    }
    Write-Host "  K8s: $(kubectl version --short 2>&1 | Select-String 'Server' | Select-Object -First 1)" -ForegroundColor Green
}

if ($DryRun) {
    Write-Host "  [DRY-RUN] 仅校验配置，不实际部署" -ForegroundColor Cyan
}

# ==========================================================================
# 1. HELM REPOS
# ==========================================================================
Write-Step "添加 Helm Repo"
$repos = @(
    @("bitnami", "https://charts.bitnami.com/bitnami"),
    @("elastic", "https://helm.elastic.co"),
    @("harbor", "https://helm.goharbor.io")
)
# 社区 chart 单独处理，失败不影响主线
$communityRepos = @(
    @("nacos-group", "https://nacos-group.github.io/nacos-helm"),
    @("apache", "https://apache.jfrog.io/artifactory/skywalking-helm"),
    @("apolloconfig", "https://apolloconfig.github.io/apollo-helm"),
    @("tdengine", "https://tdengine.github.io/helm-charts")
)

$repoErrors = @()
foreach ($r in $repos) {
    $out = helm repo add $r[0] $r[1] 2>&1
    if ($LASTEXITCODE -ne 0) { $repoErrors += "$($r[0]): $out" }
}
# 社区 repo 加了但不强求成功
foreach ($r in $communityRepos) {
    helm repo add $r[0] $r[1] 2>&1 | Out-Null
}
helm repo update 2>&1 | Out-Null

if ($repoErrors.Count -gt 0) {
    Write-Host "  [WARN] 部分 repo 添加失败:" -ForegroundColor Yellow
    $repoErrors | ForEach-Object { Write-Host "    $_" -ForegroundColor DarkGray }
} else {
    Write-Host "  主 repo 已就绪" -ForegroundColor Green
}

# ==========================================================================
# 2. NAMESPACE
# ==========================================================================
Write-Step "命名空间: $Namespace"
kubectl create ns $Namespace --dry-run=client -o yaml | kubectl apply -f -
$Global:DeployedOk = $false

# ==========================================================================
# 3. BASE LAYER
# ==========================================================================
Write-Step "--- 基础层: PostgreSQL / MySQL / Redis ---"
$pgOk = Hlm "pg" "bitnami/postgresql-ha" "$ScriptDir/config/postgresql-values.yaml" $null
if ($pgOk) {
    [void]$Info.Add(@{svc="PostgreSQL"; host="pg-postgresql-ha-pgpool.$Namespace.svc"; port=5432; user="harbor"; pass="harbordb123"})
    Write-Step "创建 Harbor 数据库 (notary_server, notary_signer)"
    ExecInPod "app.kubernetes.io/component=postgresql" @"
bash -c 'psql -U postgres -c "SELECT 1 FROM pg_database WHERE datname=''notary_server''" 2>/dev/null | grep -q 1 || psql -U postgres -c "CREATE DATABASE notary_server OWNER harbor;"'
"@ | Out-Null
    ExecInPod "app.kubernetes.io/component=postgresql" @"
bash -c 'psql -U postgres -c "SELECT 1 FROM pg_database WHERE datname=''notary_signer''" 2>/dev/null | grep -q 1 || psql -U postgres -c "CREATE DATABASE notary_signer OWNER harbor;"'
"@ | Out-Null
    ExecInPod "app.kubernetes.io/component=postgresql" @"
bash -c 'psql -U postgres -c "ALTER USER harbor CREATEDB;"'
"@ | Out-Null
}

$mysqlOk = Hlm "mysql" "bitnami/mysql" "$ScriptDir/config/mysql-values.yaml" $null
if ($mysqlOk) {
    [void]$Info.Add(@{svc="MySQL 主"; host="mysql-mysql-primary.$Namespace.svc"; port=3306; user="root"; pass="mysqlroot123"})
}

$redisOk = Hlm "redis" "bitnami/redis" "$ScriptDir/config/redis-values.yaml" $null
if ($redisOk) {
    [void]$Info.Add(@{svc="Redis 主"; host="redis-redis.$Namespace.svc"; port=6379; user="-"; pass="redispass123"})
}

# ==========================================================================
# 4. OPTIONAL: MinIO
# ==========================================================================
if ($WithMinIO) {
    Write-Step "--- MinIO 对象存储 ---"
    $ok = Hlm "minio" "bitnami/minio" $null @("--set", "auth.rootUser=minioadmin,auth.rootPassword=minioadmin", "--set", "persistence.size=50Gi", "--set", "defaultBuckets=harbor")
    if ($ok) { [void]$Info.Add(@{svc="MinIO S3"; host="minio.$Namespace.svc"; port=9000; user="minioadmin"; pass="minioadmin"}) }
}

# ==========================================================================
# 5. STORAGE / COORDINATION
# ==========================================================================
if ($WithElasticsearch) {
    Write-Step "--- Elasticsearch 3-node ---"
    $ok = Hlm "elasticsearch" "elastic/elasticsearch" "$ScriptDir/config/elasticsearch-values.yaml" $null
    if ($ok) { [void]$Info.Add(@{svc="Elasticsearch"; host="elasticsearch-master.$Namespace.svc"; port=9200; user="-"; pass="-"}) }
}

if ($WithMongoDB) {
    Write-Step "--- MongoDB 3-node ReplicaSet ---"
    $ok = Hlm "mongodb" "bitnami/mongodb" "$ScriptDir/config/mongodb-values.yaml" $null
    if ($ok) { [void]$Info.Add(@{svc="MongoDB"; host="mongodb.$Namespace.svc"; port=27017; user="root"; pass="mongoroot123"}) }
}

if ($WithZooKeeper) {
    Write-Step "--- ZooKeeper 3-node ---"
    $ok = Hlm "zookeeper" "bitnami/zookeeper" "$ScriptDir/config/zookeeper-values.yaml" $null
    if ($ok) { [void]$Info.Add(@{svc="ZooKeeper"; host="zookeeper.$Namespace.svc"; port=2181; user="-"; pass="-"}) }
}

# ==========================================================================
# 6. MESSAGING
# ==========================================================================
if ($WithKafka) {
    Write-Step "--- Kafka 3-node KRaft ---"
    $ok = Hlm "kafka" "bitnami/kafka" "$ScriptDir/config/kafka-values.yaml" $null
    if ($ok) { [void]$Info.Add(@{svc="Kafka (bootstrap)"; host="kafka-kafka-bootstrap.$Namespace.svc"; port=9092; user="-"; pass="-"}) }
}

if ($WithRocketMQ) {
    Write-Step "--- RocketMQ 3+3 (NameServer + Broker) ---"
    Write-Host "  [INFO] RocketMQ 通过原生 YAML 部署 (无 Helm chart)" -ForegroundColor DarkGray
    KubeApply "$ScriptDir/config/manifests/rocketmq.yaml"
    [void]$Info.Add(@{svc="RocketMQ NS"; host="rocketmq-namesrv.$Namespace.svc"; port=9876; user="-"; pass="-"})
    [void]$Info.Add(@{svc="RocketMQ Broker"; host="rocketmq-broker.$Namespace.svc"; port=10911; user="-"; pass="-"})
}

# ==========================================================================
# 7. SERVICE DISCOVERY & CONFIG
# ==========================================================================
if ($WithNacos) {
    Write-Step "--- Nacos 3-node ---"
    if ($mysqlOk) {
        Write-Host "  初始化 Nacos 数据库" -ForegroundColor DarkGray
        ExecInPod "app.kubernetes.io/component=primary" "mysql -uroot -pmysqlroot123 -e 'CREATE DATABASE IF NOT EXISTS nacos CHARACTER SET utf8mb4;'" | Out-Null
    } else {
        Write-Host "  [WARN] MySQL 不可用，Nacos 可能无法正常启动" -ForegroundColor Yellow
    }
    $ok = Hlm "nacos" "nacos-group/nacos" "$ScriptDir/config/nacos-values.yaml" $null
    if ($ok) { [void]$Info.Add(@{svc="Nacos"; host="nacos.$Namespace.svc"; port=8848; user="nacos"; pass="nacos"}) }
}

if ($WithApollo) {
    Write-Step "--- Apollo 3-node ---"
    if ($mysqlOk) {
        Write-Host "  初始化 Apollo 数据库" -ForegroundColor DarkGray
        ExecInPod "app.kubernetes.io/component=primary" "mysql -uroot -pmysqlroot123 -e 'CREATE DATABASE IF NOT EXISTS ApolloConfigDB CHARACTER SET utf8mb4;'" | Out-Null
        ExecInPod "app.kubernetes.io/component=primary" "mysql -uroot -pmysqlroot123 -e 'CREATE DATABASE IF NOT EXISTS ApolloPortalDB CHARACTER SET utf8mb4;'" | Out-Null
    } else {
        Write-Host "  [WARN] MySQL 不可用，Apollo 可能无法正常启动" -ForegroundColor Yellow
    }
    $ok = Hlm "apollo" "apolloconfig/apollo-service" "$ScriptDir/config/apollo-values.yaml" $null
    if ($ok) {
        [void]$Info.Add(@{svc="Apollo Portal"; host="apollo-apollo-portal.$Namespace.svc"; port=8070; user="apollo"; pass="admin"})
        [void]$Info.Add(@{svc="Apollo Config"; host="apollo-apollo-configservice.$Namespace.svc"; port=8080; user="-"; pass="-"})
    }
}

# ==========================================================================
# 8. CONTROL / APM
# ==========================================================================
if ($WithSentinel) {
    Write-Step "--- Sentinel Dashboard 2-node ---"
    Write-Host "  [INFO] Sentinel 通过原生 YAML 部署 (无 Helm chart)" -ForegroundColor DarkGray
    KubeApply "$ScriptDir/config/manifests/sentinel-dashboard.yaml"
    [void]$Info.Add(@{svc="Sentinel"; host="sentinel-dashboard.$Namespace.svc"; port=8080; user="sentinel"; pass="sentinel123"})
}

if ($WithSkyWalking) {
    Write-Step "--- SkyWalking OAP 3-node ---"
    $ok = Hlm "skywalking" "apache/skywalking-helm" "$ScriptDir/config/skywalking-values.yaml" $null
    if ($ok) {
        [void]$Info.Add(@{svc="SkyWalking OAP (gRPC)"; host="skywalking-oap.$Namespace.svc"; port=11800; user="-"; pass="-"})
        [void]$Info.Add(@{svc="SkyWalking UI"; host="skywalking-ui.$Namespace.svc"; port=8080; user="-"; pass="-"})
    }
}

# ==========================================================================
# 9. TIME-SERIES
# ==========================================================================
if ($WithTDengine) {
    Write-Step "--- TDengine 3-node ---"
    $ok = Hlm "tdengine" "tdengine/tdengine" "$ScriptDir/config/tdengine-values.yaml" $null
    if ($ok) { [void]$Info.Add(@{svc="TDengine"; host="tdengine.$Namespace.svc"; port=6030; user="root"; pass="taosdata"}) }
}

# ==========================================================================
# 10. HARBOR (镜像库)
# ==========================================================================
Write-Step "--- Harbor 镜像库 ---"
$harborExtra = @()
if ($WithIngress) {
    $harborExtra += "--set", "expose.type=ingress"
    $harborExtra += "--set", "expose.ingress.hosts.core=$IngressDomain"
}
if ($WithMinIO) {
    $harborExtra += "--set", "persistence.imageChartStorage.type=s3"
    $harborExtra += "--set", "persistence.imageChartStorage.s3.region=us-east-1"
    $harborExtra += "--set", "persistence.imageChartStorage.s3.bucket=harbor"
    $harborExtra += "--set", "persistence.imageChartStorage.s3.accesskey=minioadmin"
    $harborExtra += "--set", "persistence.imageChartStorage.s3.secretkey=minioadmin"
    $harborExtra += "--set", "persistence.imageChartStorage.s3.endpoint=http://minio.$Namespace.svc:9000"
    $harborExtra += "--set", "persistence.imageChartStorage.s3.secure=false"
}
$hOk = Hlm "harbor" "harbor/harbor" "$ScriptDir/config/harbor-values.yaml" (@("--set", "harborAdminPassword=$AdminPassword") + $harborExtra)

$nodeIP = kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}' 2>$null
if (-not $nodeIP) { $nodeIP = "localhost" }
if ($WithIngress) {
    [void]$Info.Add(@{svc="Harbor UI"; host="http://$IngressDomain"; port=80; user="admin"; pass=$AdminPassword})
} else {
    [void]$Info.Add(@{svc="Harbor UI (NodePort)"; host="http://${nodeIP}:30002"; port=30002; user="admin"; pass=$AdminPassword})
}

# ==========================================================================
# 11. SUMMARY
# ==========================================================================
Write-Step "===== 部署摘要 ====="
Write-Host ""

Write-Host "━━━ 服务连接信息 ━━━" -ForegroundColor Yellow
Write-Host ""
$Info | ForEach-Object {
    $svcName = $_.svc.PadRight(28)
    $conn = "$($_.host):$($_.port)"
    Write-Host "  $svcName $conn" -ForegroundColor Green
    if ($_.user -ne "-" -or $_.pass -ne "-") {
        $cred = "  $(''.PadRight(28))  "
        if ($_.user -and $_.user -ne "-") { $cred += "user=$($_.user)" }
        if ($_.pass -and $_.pass -ne "-") {
            if ($cred.Length -gt 30) { $cred += "  " }
            $cred += "pass=$($_.pass)"
        }
        Write-Host $cred -ForegroundColor DarkGray
    }
}

Write-Host ""
Write-Host "━━━ Pod 状态 ━━━" -ForegroundColor Yellow
kubectl get pods -n $Namespace --ignore-not-found 2>&1

Write-Host ""
Write-Host "━━━ 常用命令 ━━━" -ForegroundColor Yellow
Write-Host "  查看全部: kubectl get all -n $Namespace" -ForegroundColor Green
Write-Host "  卸载全部:" -ForegroundColor Green
Write-Host "    helm uninstall pg mysql redis kafka elasticsearch mongodb zookeeper nacos skywalking tdengine apollo harbor -n $Namespace 2>/dev/null" -ForegroundColor DarkGray
Write-Host "    kubectl delete ns $Namespace" -ForegroundColor DarkGray

if ($DryRun) {
    Write-Host "`n[DRY-RUN] 未执行任何实际部署" -ForegroundColor Cyan
}
