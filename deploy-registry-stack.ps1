param(
    [string]$Namespace = "registry-stack",
    [string]$AdminPassword = "Harbor12345",
    [string]$IngressDomain = "registry.local",

    [switch]$Pg, [switch]$Postgresql,
    [switch]$Mysql,
    [switch]$Redis,
    [switch]$MinIO,
    [switch]$Kafka,
    [switch]$Es, [switch]$Elasticsearch,
    [switch]$Mongo, [switch]$Mongodb,
    [switch]$Zk, [switch]$Zookeeper,
    [switch]$Etcd,
    [switch]$Nacos,
    [switch]$RocketMQ,
    [switch]$Sentinel,
    [switch]$Skywalking,
    [switch]$Apollo,
    [switch]$Tdengine,
    [switch]$Harbor,
    [switch]$Shardingsphere,
    [switch]$Apisix,
    [switch]$Shenyu,
    [switch]$Dubbo,
    [switch]$Seata,
    [switch]$XxlJob,
    [switch]$Prometheus,
    [switch]$Pulsar,
    [switch]$Flink,
    [switch]$Jenkins,
    [switch]$Sba, [switch]$SpringBootAdmin,
    [switch]$OpenBao,
    [switch]$Loki,
    [switch]$Velero,
    [switch]$Renovate,
    [switch]$CertManager,
    [switch]$ArgoCD,
    [switch]$Kyverno,
    [switch]$PlatformAll,
    [Alias("WithAll")]
    [switch]$All,
    [switch]$WithIngress,
    [switch]$DryRun
)

# alias mapping
if ($Postgresql) { $Pg = $true }
if ($Elasticsearch) { $Es = $true }
if ($Mongodb) { $Mongo = $true }
if ($Zookeeper) { $Zk = $true }
if ($SpringBootAdmin) { $Sba = $true }

# All shortcut
if ($All) {
    $Pg = $Mysql = $Redis = $MinIO = $Kafka = $Es = $Mongo = $Zk = $true
    $Nacos = $RocketMQ = $Sentinel = $Skywalking = $Apollo = $Tdengine = $Harbor = $Shardingsphere = $true
    $Apisix = $Shenyu = $Dubbo = $Seata = $XxlJob = $Prometheus = $Pulsar = $Flink = $Jenkins = $Sba = $true
}

# Platform shortcut; intentionally does not change the existing -All scope.
if ($PlatformAll) {
    $CertManager = $ArgoCD = $Kyverno = $Etcd = $OpenBao = $Loki = $Velero = $Renovate = $true
}

# dependency auto-resolve
if ($Nacos)  { $Mysql = $true }
if ($Apollo) { $Mysql = $true }
if ($Harbor) { $Pg = $true; $Redis = $true }
if ($Dubbo)  { $Zk = $true }
if ($XxlJob) { $Mysql = $true }
if ($Loki)   { $MinIO = $true }
if ($Velero) { $MinIO = $true }

$any = $Pg -or $Mysql -or $Redis -or $MinIO -or $Kafka -or $Es -or $Mongo -or $Zk `
     -or $Nacos -or $RocketMQ -or $Sentinel -or $Skywalking -or $Apollo -or $Tdengine -or $Harbor -or $Shardingsphere `
     -or $Apisix -or $Shenyu -or $Dubbo -or $Seata -or $XxlJob -or $Prometheus -or $Pulsar -or $Flink -or $Jenkins -or $Sba `
     -or $CertManager -or $ArgoCD -or $Kyverno -or $Etcd -or $OpenBao -or $Loki -or $Velero -or $Renovate

if (-not $any) {
    Write-Host @"
Usage: .\deploy-registry-stack.ps1 [options]

Options:
  -Pg | -Postgresql   PostgreSQL 3-node HA
  -Mysql              MySQL 3-node primary-replica
  -Redis              Redis 3-node Sentinel
  -Kafka              Kafka 3-node KRaft
  -Es | -Elasticsearch Elasticsearch 3-node
  -Mongo | -Mongodb   MongoDB 3-node ReplicaSet
  -Zk | -Zookeeper    ZooKeeper 3-node
  -Etcd               Independent etcd 3-node cluster
  -Nacos              Nacos 3-node (+MySQL)
  -RocketMQ           RocketMQ 3+3
  -Sentinel           Sentinel Dashboard 2-node
  -Skywalking         SkyWalking OAP 3-node
  -Apollo             Apollo 3-node (+MySQL)
  -Tdengine           TDengine 3-node
  -MinIO              MinIO S3 storage
  -Harbor             Harbor registry (+PG+Redis)
  -Shardingsphere     ShardingSphere proxy (+3xMySQL)
  -Apisix             Apache APISIX minimum HA (2 gateways + 3 etcd)
  -Shenyu             Apache ShenYu API gateway
  -Dubbo              Apache Dubbo-Admin (+ZK)
  -Seata              Apache Seata distributed TX
  -XxlJob             XXL-JOB scheduler (+MySQL)
  -Prometheus         Prometheus + Grafana
  -Pulsar             Apache Pulsar messaging
  -Flink              Apache Flink stream
  -Jenkins            Jenkins CI/CD
  -Sba | -SpringBootAdmin Spring Boot Admin
  -OpenBao            OpenBao 3-node Raft secret store
  -Loki               Loki HA + Alloy clustered log collection (+MinIO)
  -Velero             Velero backup controller + node agents (+MinIO)
  -Renovate           Renovate suspended CronJob
  -CertManager        cert-manager control plane
  -ArgoCD             Argo CD GitOps control plane
  -Kyverno            Kyverno policy control plane
  -PlatformAll        Deploy cert-manager/Argo CD/Kyverno + etcd/OpenBao/Loki/Velero/Renovate
  -All                Deploy everything
  -WithIngress        Enable Ingress (default NodePort)
  -DryRun             Validate only
"@
    exit 1
}

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$CFG = "$ScriptDir/config"

function step($m) { Write-Host "`n[$(Get-Date -Format HH:mm:ss)] >>> $m" -ForegroundColor Cyan }
function ok($m)   { Write-Host "  $m OK" -ForegroundColor Green }
function warn($m) { Write-Host "  [WARN] $m" -ForegroundColor Yellow }

function hlm($name, $chart, $values, $extra) {
    if ($DryRun) { Write-Host "  [DRY-RUN] helm upgrade --install $name $chart" -ForegroundColor DarkGray; return $true }
    $args = @("upgrade", "--install", $name, $chart, "--namespace", $Namespace, "--wait", "--timeout", "10m")
    if ($values) { $args += "--values"; $args += (Resolve-Path $values) }
    if ($extra)  { $args += $extra }
    try {
        $out = helm $args *>&1
        if ($LASTEXITCODE -ne 0) { warn "$name error"; $out | ForEach-Object { Write-Host "    $_" -ForegroundColor DarkGray }; return $false }
        ok $name; return $true
    } catch { warn "$name : $_"; return $false }
}

function kubeApply($file) {
    if ($DryRun) { Write-Host "  [DRY-RUN] kubectl apply -f $(Split-Path $file -Leaf)" -ForegroundColor DarkGray; return }
    $out = kubectl apply -n $Namespace -f (Resolve-Path $file) 2>&1
    if ($LASTEXITCODE -ne 0) { warn "$(Split-Path $file -Leaf) error" } else { ok $(Split-Path $file -Leaf) }
}

function execPod($label, $cmd) {
    if ($DryRun) { return $true }
    $pod = kubectl get pod -n $Namespace -l $label -o jsonpath='{.items[0].metadata.name}' 2>$null
    if (-not $pod) { return $false }
    kubectl exec -n $Namespace $pod -- bash -c $cmd 2>&1 | Out-Null; return $true
}

function Get-OfficialChart([string]$Component, [string]$Version) {
    $cacheRoot = if ($env:BEGGAR_CHART_CACHE) {
        $env:BEGGAR_CHART_CACHE
    } elseif ($env:LOCALAPPDATA) {
        Join-Path $env:LOCALAPPDATA "beggar\\charts"
    } else {
        Join-Path $HOME_DIR ".cache\\beggar\\charts"
    }
    New-Item -ItemType Directory -Path $cacheRoot -Force | Out-Null

    switch ($Component) {
        "nacos" {
            $tag = if ($Version.StartsWith("v")) { $Version } else { "v$Version" }
            $archive = Join-Path $cacheRoot "nacos-k8s-$tag.tar.gz"
            if (-not (Test-Path -LiteralPath $archive)) {
                Invoke-WebRequest -Uri "https://github.com/nacos-group/nacos-k8s/archive/refs/tags/$tag.tar.gz" -OutFile $archive
            }
            $topEntry = @(& tar.exe -tzf $archive)[0]
            if ($LASTEXITCODE -ne 0 -or -not $topEntry) { throw "Nacos Chart 压缩包无效: $archive" }
            $topDirectory = ($topEntry -split '/')[0]
            $chartPath = Join-Path (Join-Path $cacheRoot $topDirectory) "helm"
            if (-not (Test-Path -LiteralPath $chartPath)) {
                & tar.exe -xzf $archive -C $cacheRoot
                if ($LASTEXITCODE -ne 0) { throw "解压 Nacos Chart 失败: $archive" }
            }
            if (-not (Test-Path -LiteralPath $chartPath)) { throw "Nacos Chart 目录不存在: $chartPath" }
            return $chartPath
        }
        "tdengine" {
            $archive = Join-Path $cacheRoot "tdengine-$Version.tgz"
            if (-not (Test-Path -LiteralPath $archive)) {
                Invoke-WebRequest -Uri "https://raw.githubusercontent.com/taosdata/TDengine-Operator/003111e2bb4a1503fbcf760159062017def15a0b/helm/tdengine-$Version.tgz" -OutFile $archive
            }
            return $archive
        }
        default { throw "未知官方 Chart: $Component" }
    }
}

function Install-OfficialChart([string]$Component, [string]$Name, [string]$Version, [string]$Values) {
    if ($DryRun) {
        $source = if ($Component -eq "nacos") { "nacos-k8s v$Version (官方 GitHub Release)" } else { "tdengine-$Version.tgz (官方 TDengine-Operator)" }
        Write-Host "  [DRY-RUN] helm upgrade --install $Name $source --version $Version" -ForegroundColor DarkGray
        return $true
    }
    $chart = Get-OfficialChart $Component $Version
    $out = helm upgrade --install $Name $chart --namespace $Namespace --wait --timeout 10m --values (Resolve-Path $Values) 2>&1
    if ($LASTEXITCODE -ne 0) {
        warn "$Name error"
        $out | ForEach-Object { Write-Host "    $_" -ForegroundColor DarkGray }
        return $false
    }
    ok $Name
    return $true
}

function Initialize-NacosDatabase {
    if ($DryRun) {
        Write-Host "  [DRY-RUN] 初始化 Nacos MySQL schema: https://raw.githubusercontent.com/nacos-group/nacos-k8s/v1.0.2/operator/config/sql/nacos-mysql.sql" -ForegroundColor DarkGray
        return
    }
    $mysqlPod = kubectl get pod -n $Namespace -l "app.kubernetes.io/component=primary" -o jsonpath='{.items[0].metadata.name}' 2>$null
    if (-not $mysqlPod) { throw "未找到 MySQL primary Pod，无法初始化 Nacos 数据库" }
    kubectl exec -n $Namespace $mysqlPod -- mysql -uroot -pmysqlroot123 -e "CREATE DATABASE IF NOT EXISTS nacos CHARACTER SET utf8mb4;" 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "创建 Nacos 数据库失败" }
    $schemaExists = (kubectl exec -n $Namespace $mysqlPod -- mysql -N -uroot -pmysqlroot123 -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='nacos' AND table_name='config_info';" 2>$null | Out-String).Trim()
    if ($LASTEXITCODE -ne 0) { throw "检查 Nacos schema 失败" }
    if ($schemaExists -eq "1") { ok "Nacos MySQL schema"; return }
    $schema = (Invoke-WebRequest -Uri "https://raw.githubusercontent.com/nacos-group/nacos-k8s/v1.0.2/operator/config/sql/nacos-mysql.sql").Content
    $schema | kubectl exec -i -n $Namespace $mysqlPod -- mysql -uroot -pmysqlroot123 nacos 2>$null
    if ($LASTEXITCODE -ne 0) { throw "初始化 Nacos MySQL schema 失败" }
}

# precheck
step "Prechecks"
if (!(Get-Command helm -EA SilentlyContinue)) { Write-Host "Need helm" -ForegroundColor Red; exit 1 }
if (!(Get-Command kubectl -EA SilentlyContinue)) { Write-Host "Need kubectl" -ForegroundColor Red; exit 1 }
if (-not $DryRun) {
    kubectl cluster-info --request-timeout 5s 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { Write-Host "No cluster connection" -ForegroundColor Red; exit 1 }
    Write-Host "  K8s connected" -ForegroundColor Green
}

step "Helm Repos"
if ($DryRun) {
    Write-Host "  [DRY-RUN] helm repo add/update (skipped; no network or local Helm state changes)" -ForegroundColor DarkGray
} else {
helm repo add bitnami https://charts.bitnami.com/bitnami 2>$null | Out-Null
helm repo add elastic https://helm.elastic.co 2>$null | Out-Null
helm repo add harbor https://helm.goharbor.io 2>$null | Out-Null
helm repo add jetstack https://charts.jetstack.io 2>$null | Out-Null
helm repo add apache https://apache.jfrog.io/artifactory/skywalking-helm 2>$null | Out-Null
helm repo add apolloconfig https://apolloconfig.github.io/apollo-helm 2>$null | Out-Null
helm repo add argo https://argoproj.github.io/argo-helm 2>$null | Out-Null
helm repo add shenyu https://apache.github.io/shenyu-helm-chart 2>$null | Out-Null
helm repo add apisix https://apache.github.io/apisix-helm-chart 2>$null | Out-Null
helm repo add openbao https://openbao.github.io/openbao-helm 2>$null | Out-Null
helm repo add kyverno https://kyverno.github.io/kyverno 2>$null | Out-Null
helm repo add grafana-community https://grafana-community.github.io/helm-charts 2>$null | Out-Null
helm repo add grafana https://grafana.github.io/helm-charts 2>$null | Out-Null
helm repo add vmware-tanzu https://vmware-tanzu.github.io/helm-charts 2>$null | Out-Null
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts 2>$null | Out-Null
helm repo add apachepulsar https://pulsar.apache.org/charts 2>$null | Out-Null
helm repo add jenkins https://charts.jenkins.io 2>$null | Out-Null
helm repo update 2>$null | Out-Null
}
ok "Repos"

step "Namespace: $Namespace"
if ($DryRun) {
    Write-Host "  [DRY-RUN] kubectl create namespace $Namespace" -ForegroundColor DarkGray
} else {
    kubectl create ns $Namespace --dry-run=client -o yaml | kubectl apply -f - 2>&1 | Out-Null
}

# deploy components
if ($CertManager) { step "--- cert-manager ---"; hlm "cert-manager" "jetstack/cert-manager" "$CFG/cert-manager-values.yaml" $null }
if ($Mysql) { step "--- MySQL ---"; hlm "mysql" "bitnami/mysql" "$CFG/mysql-values.yaml" $null }
if ($Pg)    { step "--- PostgreSQL ---"; hlm "pg" "bitnami/postgresql-ha" "$CFG/postgresql-values.yaml" $null }
if ($Redis) { step "--- Redis ---"; hlm "redis" "bitnami/redis" "$CFG/redis-values.yaml" $null }
if ($MinIO) { step "--- MinIO ---"; hlm "minio" "bitnami/minio" "$CFG/minio-values.yaml" @("--wait-for-jobs") }

if ($Es)    { step "--- Elasticsearch ---"; hlm "elasticsearch" "elastic/elasticsearch" "$CFG/elasticsearch-values.yaml" $null }
if ($Mongo) { step "--- MongoDB ---"; hlm "mongodb" "bitnami/mongodb" "$CFG/mongodb-values.yaml" $null }
if ($Zk)    { step "--- ZooKeeper ---"; hlm "zookeeper" "bitnami/zookeeper" "$CFG/zookeeper-values.yaml" $null }
if ($Etcd)  { step "--- Independent etcd ---"; hlm "etcd" "bitnami/etcd" "$CFG/etcd-values.yaml" $null }

if ($Kafka)    { step "--- Kafka ---"; hlm "kafka" "bitnami/kafka" "$CFG/kafka-values.yaml" $null }
if ($RocketMQ) { step "--- RocketMQ ---"; kubeApply "$CFG/manifests/rocketmq.yaml" }

if ($Nacos) { step "--- Nacos ---"; Initialize-NacosDatabase; Install-OfficialChart "nacos" "nacos" "1.0.2" "$CFG/nacos-values.yaml" }
if ($Apollo) { step "--- Apollo ---"
    execPod "app.kubernetes.io/component=primary" "mysql -uroot -pmysqlroot123 -e 'CREATE DATABASE IF NOT EXISTS ApolloConfigDB CHARACTER SET utf8mb4;'" | Out-Null
    execPod "app.kubernetes.io/component=primary" "mysql -uroot -pmysqlroot123 -e 'CREATE DATABASE IF NOT EXISTS ApolloPortalDB CHARACTER SET utf8mb4;'" | Out-Null
    hlm "apollo" "apolloconfig/apollo-service" "$CFG/apollo-values.yaml" $null
}
if ($Sentinel)   { step "--- Sentinel ---"; kubeApply "$CFG/manifests/sentinel-dashboard.yaml" }
if ($Skywalking) { step "--- SkyWalking ---"; hlm "skywalking" "apache/skywalking" "$CFG/skywalking-values.yaml" $null }
if ($OpenBao) { step "--- OpenBao ---"; hlm "openbao" "openbao/openbao" "$CFG/openbao-values.yaml" @("--timeout", "15m") }
if ($ArgoCD) { step "--- Argo CD ---"; hlm "argocd" "argo/argo-cd" "$CFG/argocd-values.yaml" $null }
if ($Kyverno) { step "--- Kyverno ---"; hlm "kyverno" "kyverno/kyverno" "$CFG/kyverno-values.yaml" $null }
if ($Tdengine)   { step "--- TDengine ---"; Install-OfficialChart "tdengine" "tdengine" "3.5.0" "$CFG/tdengine-values.yaml" }
if ($Shardingsphere) { step "--- ShardingSphere ---"; kubeApply "$CFG/manifests/shardingsphere.yaml" }

if ($Apisix)     { step "--- APISIX ---"; hlm "apisix" "apisix/apisix" "$CFG/apisix-values.yaml" $null }
if ($Shenyu)     { step "--- ShenYu ---"; hlm "shenyu" "shenyu/shenyu" "$CFG/shenyu-values.yaml" $null }
if ($Dubbo)      { step "--- Dubbo-Admin ---"; kubeApply "$CFG/manifests/dubbo-admin.yaml" }
if ($Seata)      { step "--- Seata ---"; kubeApply "$CFG/manifests/seata.yaml" }
if ($XxlJob)     { step "--- XXL-JOB ---"
    if (-not $DryRun) {
        $mysqlPod = kubectl get pod -n $Namespace -l "app.kubernetes.io/component=primary" -o jsonpath='{.items[0].metadata.name}' 2>$null
        if ($mysqlPod) {
            Get-Content "$CFG/manifests/xxl-job-init.sql" -Raw | kubectl exec -i -n $Namespace $mysqlPod -- mysql -uroot -pmysqlroot123 2>$null | Out-Null
        }
    }
    kubeApply "$CFG/manifests/xxl-job.yaml"
}
if ($Prometheus) { step "--- Prometheus+Grafana ---"; hlm "prometheus" "prometheus-community/kube-prometheus-stack" "$CFG/prometheus-values.yaml" $null }
if ($Loki) {
    step "--- Loki HA + Grafana Alloy ---"
    hlm "loki" "grafana-community/loki" "$CFG/loki-values.yaml" @("--timeout", "15m")
    hlm "alloy" "grafana/alloy" "$CFG/alloy-values.yaml" $null
}
if ($Velero) { step "--- Velero ---"; hlm "velero" "vmware-tanzu/velero" "$CFG/velero-values.yaml" @("--timeout", "15m") }
if ($Renovate) { step "--- Renovate CronJob ---"; hlm "renovate" "oci://ghcr.io/renovatebot/charts/renovate" "$CFG/renovate-values.yaml" $null }
if ($Pulsar)     { step "--- Pulsar ---"; hlm "pulsar" "apachepulsar/pulsar" "$CFG/pulsar-values.yaml" @("--timeout", "15m") }
if ($Flink)      { step "--- Flink ---"; kubeApply "$CFG/manifests/flink.yaml" }
if ($Jenkins)    { step "--- Jenkins ---"; hlm "jenkins" "jenkins/jenkins" "$CFG/jenkins-values.yaml" $null }
if ($Sba)        { step "--- Spring Boot Admin ---"; kubeApply "$CFG/manifests/spring-boot-admin.yaml" }

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

step "===== Summary ====="
$nodeIP = if ($DryRun) { "localhost" } else { kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}' 2>$null }
if (-not $nodeIP) { $nodeIP = "localhost" }
Write-Host ""
if ($Pg)  { Write-Host "  PostgreSQL : pg-postgresql-ha-pgpool.$Namespace.svc:5432 (harbor / harbordb123)" -ForegroundColor Green }
if ($Mysql) { Write-Host "  MySQL      : mysql-mysql-primary.$Namespace.svc:3306 (root / mysqlroot123)" -ForegroundColor Green }
if ($Redis) { Write-Host "  Redis      : redis-redis.$Namespace.svc:6379 (redispass123)" -ForegroundColor Green }
if ($Kafka) { Write-Host "  Kafka      : kafka-kafka-bootstrap.$Namespace.svc:9092" -ForegroundColor Green }
if ($Es)    { Write-Host "  ES         : elasticsearch-master.$Namespace.svc:9200" -ForegroundColor Green }
if ($Mongo) { Write-Host "  MongoDB    : mongodb.$Namespace.svc:27017 (root / mongoroot123)" -ForegroundColor Green }
if ($Zk)    { Write-Host "  ZooKeeper  : zookeeper.$Namespace.svc:2181" -ForegroundColor Green }
if ($Etcd)  { Write-Host "  etcd       : etcd.$Namespace.svc:2379 (root / etcdroot123)" -ForegroundColor Green }
if ($Nacos) { Write-Host "  Nacos      : nacos.$Namespace.svc:8848 (nacos / nacos)" -ForegroundColor Green }
if ($RocketMQ) { Write-Host "  RocketMQ NS: rocketmq-namesrv.$Namespace.svc:9876" -ForegroundColor Green }
if ($Sentinel)  { Write-Host "  Sentinel   : sentinel-dashboard.$Namespace.svc:8080 (sentinel / sentinel123)" -ForegroundColor Green }
if ($Skywalking){ Write-Host "  SkyWalking : skywalking-oap.$Namespace.svc:11800" -ForegroundColor Green }
if ($OpenBao) { Write-Host "  OpenBao    : openbao.$Namespace.svc:8200 (waiting for init/unseal)" -ForegroundColor Green }
if ($CertManager) { Write-Host "  cert-manager: controllers + CRDs (no Issuer/Certificate created)" -ForegroundColor Green }
if ($ArgoCD) { Write-Host "  Argo CD    : https://${nodeIP}:30013 (admin / initial password secret)" -ForegroundColor Green }
if ($Kyverno) { Write-Host "  Kyverno    : admission/background/cleanup/reports controllers" -ForegroundColor Green }
if ($Apollo)    { Write-Host "  Apollo     : apollo-apollo-portal.$Namespace.svc:8070 (apollo / admin)" -ForegroundColor Green }
if ($Tdengine)  { Write-Host "  TDengine   : tdengine.$Namespace.svc:6030 (root / taosdata)" -ForegroundColor Green }
if ($Shardingsphere) { Write-Host "  ShardingSphere : shardingsphere-proxy.$Namespace.svc:3307 (MySQL sharding)" -ForegroundColor Green }
if ($Apisix)  { Write-Host "  APISIX     : http://${nodeIP}:30011" -ForegroundColor Green }
if ($Shenyu)  { Write-Host "  ShenYu     : shenyu-admin.$Namespace.svc:31095 (admin / 123456)" -ForegroundColor Green }
if ($Dubbo)   { Write-Host "  Dubbo-Admin: dubbo-admin.$Namespace.svc:8081 (root / root)" -ForegroundColor Green }
if ($Seata)   { Write-Host "  Seata      : seata-server.$Namespace.svc:8091 (file mode)" -ForegroundColor Green }
if ($XxlJob)  { Write-Host "  XXL-JOB    : xxl-job-admin.$Namespace.svc:8080 (admin / 123456)" -ForegroundColor Green }
if ($Prometheus) { Write-Host "  Prometheus : prometheus-operated.$Namespace.svc:9090" -ForegroundColor Green }
if ($Loki)    { Write-Host "  Loki       : loki-gateway.$Namespace.svc:80 (Alloy 2 replicas)" -ForegroundColor Green }
if ($Velero)  { Write-Host "  Velero     : controller + node-agent (no schedule created)" -ForegroundColor Green }
if ($Renovate) { Write-Host "  Renovate   : suspended CronJob (enable after Secret)" -ForegroundColor Green }
if ($Pulsar)  { Write-Host "  Pulsar     : pulsar-broker.$Namespace.svc:6650" -ForegroundColor Green }
if ($Flink)   { Write-Host "  Flink      : flink-jobmanager.$Namespace.svc:8081" -ForegroundColor Green }
if ($Jenkins) { Write-Host "  Jenkins    : jenkins.$Namespace.svc:8080 (admin / admin123)" -ForegroundColor Green }
if ($Sba)     { Write-Host "  Spring Boot Admin: spring-boot-admin.$Namespace.svc:8080" -ForegroundColor Green }
if ($MinIO)     { Write-Host "  MinIO      : minio.$Namespace.svc:9000 (minioadmin / minioadmin)" -ForegroundColor Green }
if ($Harbor)    { if ($WithIngress) { Write-Host "  Harbor     : http://$IngressDomain (admin / $AdminPassword)" -ForegroundColor Green } else { Write-Host "  Harbor     : http://${nodeIP}:30002 (admin / $AdminPassword)" -ForegroundColor Green } }

Write-Host ""
if (-not $DryRun) { kubectl get pods -n $Namespace --ignore-not-found 2>&1 }
if ($DryRun) { Write-Host "`n[DRY-RUN] not deployed" -ForegroundColor Cyan }
