param(
    [string]$Namespace = "registry-stack",
    [string]$AdminPassword = "Harbor12345",
    [string]$IngressDomain = "registry.local",

    # === 组件开关（全部独立，默认OFF） ===
    [switch]$Pg, [switch]$Postgresql,       # PostgreSQL 3-node
    [switch]$Mysql,                          # MySQL 3-node
    [switch]$Redis,                          # Redis 3-node Sentinel
    [switch]$MinIO,                          # MinIO 对象存储
    [switch]$Kafka,                          # Kafka 3-node KRaft
    [switch]$Es, [switch]$Elasticsearch,     # Elasticsearch 3-node
    [switch]$Mongo, [switch]$Mongodb,        # MongoDB 3-node
    [switch]$Zk, [switch]$Zookeeper,         # ZooKeeper 3-node
    [switch]$Nacos,                          # Nacos 3-node + MySQL
    [switch]$RocketMQ,                       # RocketMQ 3+3
    [switch]$Sentinel,                       # Sentinel Dashboard 2-node
    [switch]$Skywalking,                     # SkyWalking OAP 3-node
    [switch]$Apollo,                         # Apollo 3-node + MySQL
    [switch]$Tdengine,                       # TDengine 3-node
    [switch]$Harbor,                         # Harbor 镜像库 + PG + Redis
    [switch]$Shardingsphere,                 # ShardingSphere 多主分库
    [switch]$All,                            # 全部
    [switch]$WithIngress,                    # 启用 Ingress
    [switch]$DryRun                          # 校验不真跑
)

# ── 一一映射 ──
if ($Postgresql) { $Pg = $true }
if ($Elasticsearch) { $Es = $true }
if ($Mongodb) { $Mongo = $true }
if ($Zookeeper) { $Zk = $true }

# ── All 快捷 ──
if ($All) {
    $Pg = $Mysql = $Redis = $MinIO = $Kafka = $Es = $Mongo = $Zk = $true
    $Nacos = $RocketMQ = $Sentinel = $Skywalking = $Apollo = $Tdengine = $Harbor = $Shardingsphere = $true
}

# ── 依赖自动推导 ──
if ($Nacos)  { $Mysql = $true }
if ($Apollo) { $Mysql = $true }
if ($Harbor) { $Pg = $true; $Redis = $true }

# ── 无参数 → 帮助 ──
$any = $Pg -or $Mysql -or $Redis -or $MinIO -or $Kafka -or $Es -or $Mongo -or $Zk `
     -or $Nacos -or $RocketMQ -or $Sentinel -or $Skywalking -or $Apollo -or $Tdengine -or $Harbor -or $Shardingsphere
if (-not $any) {
    Write-Host @"
用法: .\deploy-registry-stack.ps1 [选项]
选项:
  -Pg | -Postgresql   PostgreSQL 3-node HA
  -Mysql              MySQL 3-node 主从
  -Redis              Redis 3-node Sentinel
  -Kafka              Kafka 3-node KRaft
  -Es | -Elasticsearch Elasticsearch 3-node
  -Mongo | -Mongodb   MongoDB 3-node ReplicaSet
  -Zk | -Zookeeper    ZooKeeper 3-node
  -Nacos              Nacos 3-node (+MySQL)
  -RocketMQ           RocketMQ 3+3
  -Sentinel           Sentinel Dashboard 2-node
  -Skywalking         SkyWalking OAP 3-node
  -Apollo             Apollo 3-node (+MySQL)
  -Tdengine           TDengine 3-node
  -MinIO              MinIO 对象存储
  -Harbor             Harbor 镜像库 (+PG+Redis)
  -Shardingsphere     ShardingSphere 多主分库 (+3xMySQL)
  -All                全部
  -WithIngress        启用 Ingress (默认 NodePort)
  -DryRun             校验配置不实际部署
"@
    exit 1
}

# ── globals ──
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$CFG = "$ScriptDir/config"

function step($m) { Write-Host "`n[$(Get-Date -Format HH:mm:ss)] >>> $m" -ForegroundColor Cyan }
function ok($m)   { Write-Host "  $m 完成" -ForegroundColor Green }
function warn($m) { Write-Host "  [WARN] $m" -ForegroundColor Yellow }

function hlm($name, $chart, $values, $extra) {
    if ($DryRun) { Write-Host "  [DRY-RUN] helm upgrade --install $name $chart" -ForegroundColor DarkGray; return $true }
    $args = @("upgrade", "--install", $name, $chart, "--namespace", $Namespace, "--wait", "--timeout", "10m")
    if ($values) { $args += "--values"; $args += (Resolve-Path $values) }
    if ($extra)  { $args += $extra }
    try {
        $out = helm $args *>&1
        if ($LASTEXITCODE -ne 0) { warn "$name 异常"; $out | %{ Write-Host "    $_" -ForegroundColor DarkGray }; return $false }
        ok $name; return $true
    } catch { warn "$name: $_"; return $false }
}

function kubeApply($file) {
    if ($DryRun) { Write-Host "  [DRY-RUN] kubectl apply -f $(Split-Path $file -Leaf)" -ForegroundColor DarkGray; return }
    $out = kubectl apply -n $Namespace -f (Resolve-Path $file) 2>&1
    if ($LASTEXITCODE -ne 0) { warn "$(Split-Path $file -Leaf) 异常" } else { ok $(Split-Path $file -Leaf) }
}

function execPod($label, $cmd) {
    $pod = kubectl get pod -n $Namespace -l $label -o jsonpath='{.items[0].metadata.name}' 2>$null
    if (-not $pod) { return $false }
    kubectl exec -n $Namespace $pod -- bash -c $cmd 2>&1 | Out-Null; return $true
}

# ════════════════════════════════
# 0. Precheck
# ════════════════════════════════
step "前提检查"
if (!(Get-Command helm -EA SilentlyContinue)) { Write-Host "需要 helm" -ForegroundColor Red; exit 1 }
if (!(Get-Command kubectl -EA SilentlyContinue)) { Write-Host "需要 kubectl" -ForegroundColor Red; exit 1 }
if (-not $DryRun) {
    kubectl cluster-info --request-timeout 5s 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { Write-Host "无法连接 K8s 集群" -ForegroundColor Red; exit 1 }
    Write-Host "  K8s 已连接" -ForegroundColor Green
}

step "Helm Repos"
@("bitnami", "elastic", "harbor", "nacos-group", "apache", "apolloconfig", "tdengine") | ForEach-Object {
    helm repo add $_ "https://charts.$_.com" 2>$null | Out-Null
}
# 修复已知 repo URL
helm repo add bitnami https://charts.bitnami.com/bitnami 2>$null | Out-Null
helm repo add elastic https://helm.elastic.co 2>$null | Out-Null
helm repo add harbor https://helm.goharbor.io 2>$null | Out-Null
helm repo add nacos-group https://nacos-group.github.io/nacos-helm 2>$null | Out-Null
helm repo add apache https://apache.jfrog.io/artifactory/skywalking-helm 2>$null | Out-Null
helm repo add apolloconfig https://apolloconfig.github.io/apollo-helm 2>$null | Out-Null
helm repo add tdengine https://tdengine.github.io/helm-charts 2>$null | Out-Null
helm repo update 2>$null | Out-Null
ok "Repos"

step "命名空间: $Namespace"
kubectl create ns $Namespace --dry-run=client -o yaml | kubectl apply -f - 2>&1 | Out-Null

# ════════════════════════════════
# 部署
# ════════════════════════════════
if ($Mysql) { step "--- MySQL ---"; hlm "mysql" "bitnami/mysql" "$CFG/mysql-values.yaml" $null }
if ($Pg)    { step "--- PostgreSQL ---"; hlm "pg" "bitnami/postgresql-ha" "$CFG/postgresql-values.yaml" $null }
if ($Redis) { step "--- Redis ---"; hlm "redis" "bitnami/redis" "$CFG/redis-values.yaml" $null }
if ($MinIO) { step "--- MinIO ---"; hlm "minio" "bitnami/minio" $null @("--set", "auth.rootUser=minioadmin,auth.rootPassword=minioadmin", "--set", "persistence.size=50Gi", "--set", "defaultBuckets=harbor") }

if ($Es)    { step "--- Elasticsearch ---"; hlm "elasticsearch" "elastic/elasticsearch" "$CFG/elasticsearch-values.yaml" $null }
if ($Mongo) { step "--- MongoDB ---"; hlm "mongodb" "bitnami/mongodb" "$CFG/mongodb-values.yaml" $null }
if ($Zk)    { step "--- ZooKeeper ---"; hlm "zookeeper" "bitnami/zookeeper" "$CFG/zookeeper-values.yaml" $null }

if ($Kafka)    { step "--- Kafka ---"; hlm "kafka" "bitnami/kafka" "$CFG/kafka-values.yaml" $null }
if ($RocketMQ) { step "--- RocketMQ ---"; kubeApply "$CFG/manifests/rocketmq.yaml" }

if ($Nacos) { step "--- Nacos ---"; execPod "app.kubernetes.io/component=primary" "mysql -uroot -pmysqlroot123 -e 'CREATE DATABASE IF NOT EXISTS nacos CHARACTER SET utf8mb4;'" | Out-Null; hlm "nacos" "nacos-group/nacos" "$CFG/nacos-values.yaml" $null }
if ($Apollo) { step "--- Apollo ---"
    execPod "app.kubernetes.io/component=primary" "mysql -uroot -pmysqlroot123 -e 'CREATE DATABASE IF NOT EXISTS ApolloConfigDB CHARACTER SET utf8mb4;'" | Out-Null
    execPod "app.kubernetes.io/component=primary" "mysql -uroot -pmysqlroot123 -e 'CREATE DATABASE IF NOT EXISTS ApolloPortalDB CHARACTER SET utf8mb4;'" | Out-Null
    hlm "apollo" "apolloconfig/apollo-service" "$CFG/apollo-values.yaml" $null
}
if ($Sentinel)   { step "--- Sentinel ---"; kubeApply "$CFG/manifests/sentinel-dashboard.yaml" }
if ($Skywalking) { step "--- SkyWalking ---"; hlm "skywalking" "apache/skywalking-helm" "$CFG/skywalking-values.yaml" $null }
if ($Tdengine)   { step "--- TDengine ---"; hlm "tdengine" "tdengine/tdengine" "$CFG/tdengine-values.yaml" $null }
if ($Shardingsphere) { step "--- ShardingSphere ---"; kubeApply "$CFG/manifests/shardingsphere.yaml" }

if ($Harbor) {
    step "--- Harbor ---"
    $extra = @()
    if ($WithIngress) { $extra += "--set", "expose.type=ingress"; $extra += "--set", "expose.ingress.hosts.core=$IngressDomain" }
    if ($MinIO) {
        $extra += "--set", "persistence.imageChartStorage.type=s3"
        $extra += "--set", "persistence.imageChartStorage.s3.region=us-east-1"
        $extra += "--set", "persistence.imageChartStorage.s3.bucket=harbor"
        $extra += "--set", "persistence.imageChartStorage.s3.accesskey=minioadmin"
        $extra += "--set", "persistence.imageChartStorage.s3.secretkey=minioadmin"
        $extra += "--set", "persistence.imageChartStorage.s3.endpoint=http://minio.$Namespace.svc:9000"
        $extra += "--set", "persistence.imageChartStorage.s3.secure=false"
    }
    hlm "harbor" "harbor/harbor" "$CFG/harbor-values.yaml" (@("--set", "harborAdminPassword=$AdminPassword") + $extra)
}

# ════════════════════════════════
# 摘要
# ════════════════════════════════
step "===== 摘要 ====="
$nodeIP = kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}' 2>$null
if (-not $nodeIP) { $nodeIP = "localhost" }
Write-Host ""
if ($Pg)  { Write-Host "  PostgreSQL : pg-postgresql-ha-pgpool.$Namespace.svc:5432 (harbor / harbordb123)" -ForegroundColor Green }
if ($Mysql) { Write-Host "  MySQL      : mysql-mysql-primary.$Namespace.svc:3306 (root / mysqlroot123)" -ForegroundColor Green }
if ($Redis) { Write-Host "  Redis      : redis-redis.$Namespace.svc:6379 (redispass123)" -ForegroundColor Green }
if ($Kafka) { Write-Host "  Kafka      : kafka-kafka-bootstrap.$Namespace.svc:9092" -ForegroundColor Green }
if ($Es)    { Write-Host "  ES         : elasticsearch-master.$Namespace.svc:9200" -ForegroundColor Green }
if ($Mongo) { Write-Host "  MongoDB    : mongodb.$Namespace.svc:27017 (root / mongoroot123)" -ForegroundColor Green }
if ($Zk)    { Write-Host "  ZooKeeper  : zookeeper.$Namespace.svc:2181" -ForegroundColor Green }
if ($Nacos) { Write-Host "  Nacos      : nacos.$Namespace.svc:8848 (nacos / nacos)" -ForegroundColor Green }
if ($RocketMQ) { Write-Host "  RocketMQ NS: rocketmq-namesrv.$Namespace.svc:9876" -ForegroundColor Green }
if ($Sentinel)  { Write-Host "  Sentinel   : sentinel-dashboard.$Namespace.svc:8080 (sentinel / sentinel123)" -ForegroundColor Green }
if ($Skywalking){ Write-Host "  SkyWalking : skywalking-oap.$Namespace.svc:11800" -ForegroundColor Green }
if ($Apollo)    { Write-Host "  Apollo     : apollo-apollo-portal.$Namespace.svc:8070 (apollo / admin)" -ForegroundColor Green }
if ($Tdengine)  { Write-Host "  TDengine   : tdengine.$Namespace.svc:6030 (root / taosdata)" -ForegroundColor Green }
if ($Shardingsphere) { Write-Host "  ShardingSphere : shardingsphere-proxy.$Namespace.svc:3307 (MySQL协议)" -ForegroundColor Green }
if ($MinIO)     { Write-Host "  MinIO      : minio.$Namespace.svc:9000 (minioadmin / minioadmin)" -ForegroundColor Green }
if ($Harbor)    { if ($WithIngress) { Write-Host "  Harbor     : http://$IngressDomain (admin / $AdminPassword)" -ForegroundColor Green } else { Write-Host "  Harbor     : http://${nodeIP}:30002 (admin / $AdminPassword)" -ForegroundColor Green } }

Write-Host ""
kubectl get pods -n $Namespace --ignore-not-found 2>&1
if ($DryRun) { Write-Host "`n[DRY-RUN] 未部署" -ForegroundColor Cyan }
