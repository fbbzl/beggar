#!/usr/bin/env bash
set -euo pipefail

# ═══════════════════════════════════════════════════════════
# deploy-registry-stack.sh — Linux bash 版
# 每个组件独立开关，Helm 自动处理依赖
# ═══════════════════════════════════════════════════════════
# 用法:
#   bash deploy-registry-stack.sh --mysql               # 只装 MySQL
#   bash deploy-registry-stack.sh --mysql --redis       # MySQL + Redis
#   bash deploy-registry-stack.sh --all                 # 全量
#   bash deploy-registry-stack.sh --platform-all        # 研发平台补充工具
#   DRY_RUN=1 bash deploy-registry-stack.sh --mysql     # 校验不真跑
# ═══════════════════════════════════════════════════════════

NAMESPACE="${NAMESPACE:-registry-stack}"
ADMIN_PASS="${ADMIN_PASS:-Harbor12345}"
WITH_INGRESS="${WITH_INGRESS:-}"
INGRESS_DOMAIN="${INGRESS_DOMAIN:-registry.local}"
DRY_RUN="${DRY_RUN:-}"

# ── Colors ──
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; GRAY='\033[0;90m'; NC='\033[0m'
step()   { echo -e "\n[$(date +%H:%M:%S)] >>> ${CYAN}$*${NC}"; }
info()   { echo -e "  ${GREEN}$*${NC}"; }
ok()     { echo -e "  ${GREEN}✓ $*${NC}"; }
warn()   { echo -e "  ${YELLOW}⚠ $*${NC}"; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CFG="$SCRIPT_DIR/config"

# Centralized defaults keep chart and manifest versions reviewable in one place.
set -a
# shellcheck disable=SC1091
. "$CFG/versions.env"
set +a
BEGGAR_VERSION_OVERRIDES="${BEGGAR_VERSION_OVERRIDES:-}"

version_override() {
  local component=$1 pair key value
  component=${component//-/_}; component=${component^^}
  [ -n "$BEGGAR_VERSION_OVERRIDES" ] || return 0
  IFS=',' read -r -a pairs <<< "$BEGGAR_VERSION_OVERRIDES"
  for pair in "${pairs[@]}"; do
    key=${pair%%=*}; value=${pair#*=}; key=${key//-/_}; key=${key^^}
    [ "$key" = "$component" ] || continue
    [[ "$value" =~ ^[A-Za-z0-9][A-Za-z0-9._+:-]*$ ]] || {
      echo "版本格式不正确: $component=$value" >&2
      exit 1
    }
    printf '%s' "$value"
    return 0
  done
}

image_version() {
  local component=$1 override default_name default
  component=${component//-/_}; component=${component^^}
  override=$(version_override "IMAGE_${component}")
  case "$component" in
    MYSQL|REDIS|MINIO) ;;
    *) [ -n "$override" ] || override=$(version_override "$component") ;;
  esac
  [ -n "$override" ] && { printf '%s' "$override"; return 0; }
  default_name="DEFAULT_IMAGE_TAG_${component}"
  default=${!default_name:-}
  [ -n "$default" ] && printf '%s' "$default"
  return 0
}

component_version() {
  local component=$1 override default_name default
  case "$component" in
    cert-manager) component=CERT_MANAGER ;;
    elasticsearch) component=ES ;;
    mongodb) component=MONGO ;;
    postgresql|postgres) component=PG ;;
    zookeeper) component=ZK ;;
    skywalking) component=SKYWALKING ;;
    argocd) component=ARGOCD ;;
    kyverno) component=KYVERNO ;;
    openbao) component=OPENBAO ;;
    prometheus) component=PROMETHEUS ;;
    *) component=${component^^} ;;
  esac
  override=$(version_override "$component")
  [ -n "$override" ] && { printf '%s' "$override"; return 0; }
  default_name="DEFAULT_CHART_VERSION_${component}"
  default=${!default_name:-}
  [ -n "$default" ] && printf '%s' "$default"
  return 0
}

validate_version_overrides() {
  local pair key value normalized local_component seen
  local allowed="CERT_MANAGER MYSQL PG REDIS MINIO ES MONGO ZK ETCD KAFKA SKYWALKING APOLLO OPENBAO ARGOCD KYVERNO APISIX SHENYU PROMETHEUS LOKI ALLOY VELERO RENOVATE PULSAR JENKINS SENTINEL FLINK ROCKETMQ SEATA DUBBO XXL_JOB SHARDINGSPHERE POSTGRES NACOS TDENGINE SPRING_BOOT_ADMIN"
  local -a seen_keys=()
  [ -n "$BEGGAR_VERSION_OVERRIDES" ] || return 0
  IFS=',' read -r -a pairs <<< "$BEGGAR_VERSION_OVERRIDES"
  for pair in "${pairs[@]}"; do
    key=${pair%%=*}; value=${pair#*=}
    [[ "$key" =~ ^[A-Za-z][A-Za-z0-9_-]*$ && "$pair" == *=* ]] || {
      echo "版本覆盖格式不正确，应为 component=version,...: $pair" >&2
      exit 1
    }
    normalized=${key//-/_}; normalized=${normalized^^}
    local_component=$normalized
    if [[ "$local_component" == IMAGE_* ]]; then
      local_component=${local_component#IMAGE_}
    fi
    [[ " $allowed " == *" $local_component "* ]] || {
      echo "不支持的版本组件: $key" >&2
      exit 1
    }
    for seen in "${seen_keys[@]:-}"; do
      [ "$seen" = "$normalized" ] && {
        echo "版本组件重复: $key" >&2
        exit 1
      }
    done
    seen_keys+=("$normalized")
    [[ "$value" =~ ^[A-Za-z0-9][A-Za-z0-9._+:-]*$ ]] || {
      echo "版本格式不正确: $pair" >&2
      exit 1
    }
  done
}

unavailable_component() {
  local component=$1 reason=$2
  if [ -n "$DRY_RUN" ]; then
    warn "$component 暂不执行：$reason"
    return 0
  fi
  echo "${RED}[FATAL] $component 暂不支持自动部署：$reason${NC}" >&2
  exit 1
}

validate_component_support() {
  [ -n "$NACOS" ] && [ -z "$DRY_RUN" ] && unavailable_component "Nacos" "官方 Chart 需要从 nacos-k8s 仓库本地安装，当前脚本未自动下载"
  [ -n "$TDENGINE" ] && [ -z "$DRY_RUN" ] && unavailable_component "TDengine" "仓库地址已失效，未找到可核验的官方 Helm Chart 来源"
  return 0
}

# ── 全部组件初始 OFF ──
PG=; MYSQL=; REDIS=; MINIO=; KAFKA=; ES=; MONGO=; ZK=;
NACOS=; ROCKETMQ=; SENTINEL=; SKYWALKING=; APOLLO=; TDENGINE=; HARBOR=; SHARDINGSPHERE=
APISIX=; SHENYU=; DUBBO=; SEATA=; XXL_JOB=; PROMETHEUS=; PULSAR=; FLINK=; JENKINS=; SBA=
CERT_MANAGER=; ARGOCD=; KYVERNO=
ETCD=; OPENBAO=; LOKI=; VELERO=; RENOVATE=; PLATFORM_ALL=; ALL=

# ── 参数解析 ──
while [ $# -gt 0 ]; do
  case "$1" in
    --pg|--postgresql)  PG=1 ;;
    --mysql)            MYSQL=1 ;;
    --redis)            REDIS=1 ;;
    --kafka)            KAFKA=1 ;;
    --es|--elasticsearch) ES=1 ;;
    --mongo|--mongodb)  MONGO=1 ;;
    --zk|--zookeeper)   ZK=1 ;;
    --etcd)             ETCD=1 ;;
    --nacos)            NACOS=1 ;;
    --rocketmq)         ROCKETMQ=1 ;;
    --sentinel)         SENTINEL=1 ;;
    --skywalking)       SKYWALKING=1 ;;
    --apollo)           APOLLO=1 ;;
    --tdengine)         TDENGINE=1 ;;
    --minio)            MINIO=1 ;;
    --harbor)           HARBOR=1 ;;
    --shardingsphere)   SHARDINGSPHERE=1 ;;
    --apisix)           APISIX=1 ;;
    --shenyu)           SHENYU=1 ;;
    --dubbo)            DUBBO=1 ;;
    --seata)            SEATA=1 ;;
    --xxl-job)          XXL_JOB=1 ;;
    --prometheus)       PROMETHEUS=1 ;;
    --pulsar)           PULSAR=1 ;;
    --flink)            FLINK=1 ;;
    --jenkins)          JENKINS=1 ;;
    --spring-boot-admin) SBA=1 ;;
    -sba)               SBA=1 ;;
    --openbao)          OPENBAO=1 ;;
    --loki)             LOKI=1 ;;
    --velero)           VELERO=1 ;;
    --renovate)         RENOVATE=1 ;;
    --cert-manager)     CERT_MANAGER=1 ;;
    --argocd)           ARGOCD=1 ;;
    --kyverno)          KYVERNO=1 ;;
    --platform-all)     PLATFORM_ALL=1 ;;
    --all)              ALL=1 ;;
    --ingress)          WITH_INGRESS=1 ;;
    --domain)           INGRESS_DOMAIN="$2"; shift ;;
    --dry-run)          DRY_RUN=1 ;;
    --version-overrides) BEGGAR_VERSION_OVERRIDES="$2"; shift ;;
    -h|--help)
      echo "用法: bash $0 [选项]"
      echo "选项:"
      echo "  --pg|--postgresql   PostgreSQL 3-node HA"
      echo "  --mysql             MySQL 3-node 主从"
      echo "  --redis             Redis 3-node Sentinel"
      echo "  --kafka             Kafka 3-node KRaft"
      echo "  --es|--elasticsearch Elasticsearch 3-node"
      echo "  --mongo|--mongodb   MongoDB 3-node ReplicaSet"
      echo "  --zk|--zookeeper    ZooKeeper 3-node"
      echo "  --etcd              Independent etcd 3-node cluster"
      echo "  --nacos             Nacos 3-node (+MySQL)"
      echo "  --rocketmq          RocketMQ 3+3"
      echo "  --sentinel          Sentinel Dashboard 2-node"
      echo "  --skywalking        SkyWalking OAP 3-node"
      echo "  --apollo            Apollo 3-node (+MySQL)"
      echo "  --tdengine          TDengine 3-node"
      echo "  --minio             MinIO 对象存储"
      echo "  --harbor            Harbor 镜像库 (+PG+Redis)"
      echo "  --shardingsphere    ShardingSphere 多主分库 (+3xMySQL)"
      echo "  --apisix            Apache APISIX minimum HA (2 gateways + 3 etcd)"
      echo "  --shenyu            Apache ShenYu API 网关 (+admin+bootstrap)"
      echo "  --dubbo             Apache Dubbo-Admin (+ZK)"
      echo "  --seata             Apache Seata 分布式事务 (file模式)"
      echo "  --xxl-job           XXL-JOB 分布式调度 (+MySQL)"
      echo "  --prometheus        Prometheus + Grafana 监控栈"
      echo "  --pulsar            Apache Pulsar 消息队列"
      echo "  --flink             Apache Flink 流计算"
      echo "  --jenkins           Jenkins CI/CD"
      echo "  --spring-boot-admin | -sba Spring Boot Admin 应用监控"
      echo "  --openbao           OpenBao 3-node Raft secret store"
      echo "  --loki              Loki HA + Alloy clustered log collection (+MinIO)"
      echo "  --velero            Velero backup controller + node agents (+MinIO)"
      echo "  --renovate          Renovate suspended CronJob"
      echo "  --cert-manager      cert-manager control plane"
      echo "  --argocd            Argo CD GitOps control plane"
      echo "  --kyverno           Kyverno policy control plane"
      echo "  --platform-all      Deploy cert-manager/Argo CD/Kyverno + etcd/OpenBao/Loki/Velero/Renovate"
      echo "  --all               全部"
      echo "  --ingress           启用 Ingress (默认 NodePort)"
      echo "  --domain <d>        Ingress 域名 (默认 registry.local)"
      echo "  --dry-run           校验配置不实际部署"
      echo "  --version-overrides 组件=版本,... 覆盖 Helm Chart 或原生清单镜像标签"
      echo ""
      echo "环境变量: NAMESPACE, ADMIN_PASS, DRY_RUN, BEGGAR_VERSION_OVERRIDES（未知或重复组件会拒绝）"
      exit 0
      ;;
    *) echo "未知选项: $1 (--help 查看帮助)"; exit 1 ;;
  esac
  shift
done

validate_version_overrides

# ── --all 快捷 ──
[ -n "$ALL" ] && PG=1 MYSQL=1 REDIS=1 MINIO=1 KAFKA=1 ES=1 MONGO=1 ZK=1 \
    NACOS=1 ROCKETMQ=1 SENTINEL=1 SKYWALKING=1 APOLLO=1 TDENGINE=1 HARBOR=1 SHARDINGSPHERE=1 \
    APISIX=1 SHENYU=1 DUBBO=1 SEATA=1 XXL_JOB=1 PROMETHEUS=1 PULSAR=1 FLINK=1 JENKINS=1 SBA=1

# ── --platform-all 快捷（不改变现有 --all 的范围）──
[ -n "$PLATFORM_ALL" ] && CERT_MANAGER=1 ARGOCD=1 KYVERNO=1 ETCD=1 OPENBAO=1 LOKI=1 VELERO=1 RENOVATE=1

# ── 依赖自动推导 ──
[ -n "$NACOS" ]   && MYSQL=1    # Nacos 需要 MySQL
[ -n "$APOLLO" ]  && MYSQL=1    # Apollo 需要 MySQL
[ -n "$HARBOR" ]  && PG=1 REDIS=1  # Harbor 需要 PG + Redis
[ -n "$DUBBO" ]   && ZK=1       # Dubbo 需要 ZK 作为注册中心
[ -n "$XXL_JOB" ] && MYSQL=1    # XXL-JOB 需要 MySQL
[ -n "$LOKI" ]    && MINIO=1    # Loki 使用 S3 对象存储
[ -n "$VELERO" ]  && MINIO=1    # Velero 使用 S3 备份存储

validate_component_support

# ── 无参数 → 显示帮助 ──
if [ -z "$PG$MYSQL$REDIS$MINIO$KAFKA$ES$MONGO$ZK$NACOS$ROCKETMQ$SENTINEL$SKYWALKING$APOLLO$TDENGINE$HARBOR$SHARDINGSPHERE$APISIX$SHENYU$DUBBO$SEATA$XXL_JOB$PROMETHEUS$PULSAR$FLINK$JENKINS$SBA$ETCD$OPENBAO$LOKI$VELERO$RENOVATE" ]; then
  echo "请指定要部署的组件，例如: bash $0 --mysql"
  echo "查看全部选项: bash $0 --help"
  exit 1
fi

# ══════════════════════════════════
# 工具函数
# ══════════════════════════════════
hlm() {
  local name=$1 chart=$2 values=$3; shift 3
  local component=${name//-/_} version
  version=$(component_version "$component")
  if [ -n "$DRY_RUN" ]; then
    echo -e "  ${GRAY}[DRY-RUN] helm upgrade --install $name $chart${version:+ --version $version}${NC}"
    return 0
  fi
  local args=(upgrade --install "$name" "$chart" --namespace "$NAMESPACE" --wait --timeout 10m)
  [ -n "$version" ] && args+=(--version "$version")
  [ -n "$values" ] && args+=(--values "$values")
  [ $# -gt 0 ] && args+=("$@")
  local out
  out=$(helm "${args[@]}" 2>&1) || {
    warn "$name 部署异常"; echo "$out" | while IFS= read -r l; do echo -e "    ${GRAY}$l${NC}"; done
    exit 1
  }
  ok "$name"; return 0
}

kube_apply() {
  local file=$1 base=$(basename "$1") tag image_tags=""
  local -a sed_args=()
  case "$base" in
    minio.yaml) tag=$(image_version MINIO); image_tags="minio=$tag"; sed_args+=(-e "s#minio/minio:[^[:space:]]+#minio/minio:$tag#g") ;;
    sentinel-dashboard.yaml) tag=$(image_version SENTINEL); image_tags="sentinel=$tag"; sed_args+=(-e "s#sentinel-dashboard:[^\"[:space:]]+#sentinel-dashboard:$tag#g") ;;
    flink.yaml) tag=$(image_version FLINK); image_tags="flink=$tag"; sed_args+=(-e "s#flink:[^[:space:]]+#flink:$tag#g") ;;
    redis-sentinel.yaml) tag=$(image_version REDIS); image_tags="redis=$tag"; sed_args+=(-e "s#redis:[^[:space:]]+#redis:$tag#g") ;;
    mysql-replication.yaml) tag=$(image_version MYSQL); image_tags="mysql=$tag"; sed_args+=(-e "s#mysql:[^[:space:]]+#mysql:$tag#g") ;;
    shardingsphere.yaml)
      tag=$(image_version MYSQL); image_tags="mysql=$tag"; sed_args+=(-e "s#mysql:[^[:space:]]+#mysql:$tag#g")
      tag=$(image_version SHARDINGSPHERE); sed_args+=(-e "s#apache/shardingsphere-proxy:[^[:space:]]+#apache/shardingsphere-proxy:$tag#g")
      image_tags+=",shardingsphere=$tag"
      ;;
    rocketmq.yaml) tag=$(image_version ROCKETMQ); image_tags="rocketmq=$tag"; sed_args+=(-e "s#apache/rocketmq:[^[:space:]]+#apache/rocketmq:$tag#g") ;;
    seata.yaml) tag=$(image_version SEATA); image_tags="seata=$tag"; sed_args+=(-e "s#apache/seata-server:[^[:space:]]+#apache/seata-server:$tag#g") ;;
    dubbo-admin.yaml) tag=$(image_version DUBBO); image_tags="dubbo=$tag"; sed_args+=(-e "s#apache/dubbo-admin:[^[:space:]]+#apache/dubbo-admin:$tag#g") ;;
    xxl-job.yaml) tag=$(image_version XXL_JOB); image_tags="xxl-job=$tag"; sed_args+=(-e "s#xuxueli/xxl-job-admin:[^[:space:]]+#xuxueli/xxl-job-admin:$tag#g") ;;
    spring-boot-admin.yaml) tag=$(image_version SPRING_BOOT_ADMIN); image_tags="spring-boot-admin=$tag"; sed_args+=(-e "s#codecentric/spring-boot-admin-server:[^[:space:]]+#codecentric/spring-boot-admin-server:$tag#g") ;;
  esac
  [ -n "$DRY_RUN" ] && echo -e "  ${GRAY}[DRY-RUN] kubectl apply -f $base${image_tags:+ (image tags $image_tags)}${NC}" && return 0
  local out
  if [ ${#sed_args[@]} -gt 0 ]; then
    out=$(sed "${sed_args[@]}" "$file" | kubectl apply -n "$NAMESPACE" -f - 2>&1) || {
      warn "$base 异常"; echo "$out" | while IFS= read -r l; do echo -e "  ${GRAY}$l${NC}"; done; exit 1;
    }
  else
    out=$(kubectl apply -n "$NAMESPACE" -f "$file" 2>&1) || {
      warn "$base 异常"; echo "$out" | while IFS= read -r l; do echo -e "  ${GRAY}$l${NC}"; done; exit 1;
    }
  fi
  {
    ok "$base"
  }
}

exec_pod() {
  [ -n "$DRY_RUN" ] && return 0
  local pod; pod=$(kubectl get pod -n "$NAMESPACE" -l "$1" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
  [ -z "$pod" ] && return 1
  kubectl exec -n "$NAMESPACE" "$pod" -- bash -c "$2" &>/dev/null || true
}

# ══════════════════════════════════
# 0. 前提
# ══════════════════════════════════
step "前提检查"
if [ -z "$DRY_RUN" ]; then
  command -v kubectl &>/dev/null || { echo "需要 kubectl" >&2; exit 1; }
  command -v helm &>/dev/null   || { echo "需要 helm" >&2; exit 1; }
  kubectl cluster-info --request-timeout 5s &>/dev/null || { echo "无法连接 K8s" >&2; exit 1; }
  info "K8s 已连接"
fi

step "准备所选组件的 Helm Repo"
REPO_NAMES=()
ensure_repo() {
  local name=$1 url=$2 existing
  for existing in "${REPO_NAMES[@]:-}"; do
    [ "$existing" = "$name" ] && return 0
  done
  REPO_NAMES+=("$name")
  if [ -n "$DRY_RUN" ]; then
    echo "[DRY-RUN] helm repo add $name $url"
  else
    helm repo add "$name" "$url" --force-update >/dev/null
  fi
}

[ -n "$CERT_MANAGER" ] && ensure_repo jetstack https://charts.jetstack.io
[ -n "$PG$MYSQL$REDIS$MINIO$MONGO$ZK$ETCD$KAFKA" ] && ensure_repo bitnami https://charts.bitnami.com/bitnami
[ -n "$ES" ] && ensure_repo elastic https://helm.elastic.co
[ -n "$HARBOR" ] && ensure_repo harbor https://helm.goharbor.io
[ -n "$SKYWALKING" ] && ensure_repo apache https://apache.jfrog.io/artifactory/skywalking-helm
[ -n "$APOLLO" ] && ensure_repo apolloconfig https://charts.apolloconfig.com
[ -n "$ARGOCD" ] && ensure_repo argo https://argoproj.github.io/argo-helm
[ -n "$SHENYU" ] && ensure_repo shenyu https://apache.github.io/shenyu-helm-chart
[ -n "$APISIX" ] && ensure_repo apisix https://charts.apiseven.com
[ -n "$OPENBAO" ] && ensure_repo openbao https://openbao.github.io/openbao-helm
[ -n "$KYVERNO" ] && ensure_repo kyverno https://kyverno.github.io/kyverno
[ -n "$LOKI" ] && ensure_repo grafana-community https://grafana-community.github.io/helm-charts
[ -n "$LOKI" ] && ensure_repo grafana https://grafana.github.io/helm-charts
[ -n "$VELERO" ] && ensure_repo vmware-tanzu https://vmware-tanzu.github.io/helm-charts
[ -n "$PROMETHEUS" ] && ensure_repo prometheus-community https://prometheus-community.github.io/helm-charts
[ -n "$PULSAR" ] && ensure_repo apachepulsar https://pulsar.apache.org/charts
[ -n "$JENKINS" ] && ensure_repo jenkins https://charts.jenkins.io
if [ -n "$DRY_RUN" ]; then
  echo "[DRY-RUN] helm repo update ${REPO_NAMES[*]}"
elif [ ${#REPO_NAMES[@]} -gt 0 ]; then
  helm repo update "${REPO_NAMES[@]}"
fi
ok "Repos 就绪"

step "命名空间: $NAMESPACE"
if [ -n "$DRY_RUN" ]; then
  echo -e "  ${GRAY}[DRY-RUN] kubectl create namespace $NAMESPACE${NC}"
else
  kubectl create ns "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f - &>/dev/null
fi

# ══════════════════════════════════
# 逐组件部署
# ══════════════════════════════════

# -- 基础存储 --
[ -n "$CERT_MANAGER" ] && step "--- cert-manager ---" && \
  hlm "cert-manager" "jetstack/cert-manager" "$CFG/cert-manager-values.yaml"

[ -n "$MYSQL" ] && step "--- MySQL 3-node ---" && \
  hlm "mysql" "bitnami/mysql" "$CFG/mysql-values.yaml"

[ -n "$PG" ] && step "--- PostgreSQL 3-node ---" && \
  hlm "pg" "bitnami/postgresql-ha" "$CFG/postgresql-values.yaml" && {
    exec_pod "app.kubernetes.io/component=postgresql" \
      "psql -U postgres -c \"SELECT 1 FROM pg_database WHERE datname='notary_server'\" 2>/dev/null | grep -q 1 || psql -U postgres -c \"CREATE DATABASE notary_server OWNER harbor;\""
    exec_pod "app.kubernetes.io/component=postgresql" \
      "psql -U postgres -c \"SELECT 1 FROM pg_database WHERE datname='notary_signer'\" 2>/dev/null | grep -q 1 || psql -U postgres -c \"CREATE DATABASE notary_signer OWNER harbor;\""
    exec_pod "app.kubernetes.io/component=postgresql" \
      "psql -U postgres -c \"ALTER USER harbor CREATEDB;\""
  }

[ -n "$REDIS" ] && step "--- Redis 3-node ---" && \
  hlm "redis" "bitnami/redis" "$CFG/redis-values.yaml"

[ -n "$MINIO" ] && step "--- MinIO ---" && \
  hlm "minio" "bitnami/minio" "$CFG/minio-values.yaml" --wait-for-jobs

# -- 存储 / 协调 --
[ -n "$ES" ]    && step "--- Elasticsearch 3-node ---" && \
  hlm "elasticsearch" "elastic/elasticsearch" "$CFG/elasticsearch-values.yaml"
[ -n "$MONGO" ] && step "--- MongoDB 3-node ---" && \
  hlm "mongodb" "bitnami/mongodb" "$CFG/mongodb-values.yaml"
[ -n "$ZK" ]    && step "--- ZooKeeper 3-node ---" && \
  hlm "zookeeper" "bitnami/zookeeper" "$CFG/zookeeper-values.yaml"
[ -n "$ETCD" ]  && step "--- Independent etcd 3-node ---" && \
  hlm "etcd" "bitnami/etcd" "$CFG/etcd-values.yaml"

# -- 消息 --
[ -n "$KAFKA" ]    && step "--- Kafka 3-node ---" && \
  hlm "kafka" "bitnami/kafka" "$CFG/kafka-values.yaml"
[ -n "$ROCKETMQ" ] && step "--- RocketMQ ---" && \
  kube_apply "$CFG/manifests/rocketmq.yaml"

# -- 注册 / 配置 --
[ -n "$NACOS" ] && step "--- Nacos 3-node ---" && {
  unavailable_component "Nacos" "官方 Chart 需要从 nacos-k8s 仓库本地安装，当前脚本未自动下载"
  if [ -n "$DRY_RUN" ]; then
    :
  else
    exec_pod "app.kubernetes.io/component=primary" \
      "mysql -uroot -pmysqlroot123 -e 'CREATE DATABASE IF NOT EXISTS nacos CHARACTER SET utf8mb4;'" || true
    hlm "nacos" "nacos-group/nacos" "$CFG/nacos-values.yaml"
  fi
}

[ -n "$APOLLO" ] && step "--- Apollo 3-node ---" && {
  exec_pod "app.kubernetes.io/component=primary" \
    "mysql -uroot -pmysqlroot123 -e 'CREATE DATABASE IF NOT EXISTS ApolloConfigDB CHARACTER SET utf8mb4;'" || true
  exec_pod "app.kubernetes.io/component=primary" \
    "mysql -uroot -pmysqlroot123 -e 'CREATE DATABASE IF NOT EXISTS ApolloPortalDB CHARACTER SET utf8mb4;'" || true
  hlm "apollo" "apolloconfig/apollo-service" "$CFG/apollo-values.yaml"
}

# -- 控制 / APM --
[ -n "$SENTINEL" ]   && step "--- Sentinel Dashboard ---" && \
  kube_apply "$CFG/manifests/sentinel-dashboard.yaml"
[ -n "$SKYWALKING" ] && step "--- SkyWalking 3-node ---" && \
  hlm "skywalking" "apache/skywalking-helm" "$CFG/skywalking-values.yaml"

# -- 密钥管理 --
[ -n "$OPENBAO" ] && step "--- OpenBao 3-node Raft ---" && \
  hlm "openbao" "openbao/openbao" "$CFG/openbao-values.yaml" --timeout 15m

[ -n "$ARGOCD" ] && step "--- Argo CD GitOps ---" && \
  hlm "argocd" "argo/argo-cd" "$CFG/argocd-values.yaml"

[ -n "$KYVERNO" ] && step "--- Kyverno policy ---" && \
  hlm "kyverno" "kyverno/kyverno" "$CFG/kyverno-values.yaml"

# -- 时序 --
[ -n "$TDENGINE" ] && step "--- TDengine 3-node ---" && \
  unavailable_component "TDengine" "仓库地址已失效，未找到可核验的官方 Helm Chart 来源"

# -- 分库 --
[ -n "$SHARDINGSPHERE" ] && step "--- ShardingSphere-Proxy 多主分库 ---" && \
  kube_apply "$CFG/manifests/shardingsphere.yaml"

# -- API 网关 --
[ -n "$APISIX" ] && step "--- APISIX 网关 ---" && \
  hlm "apisix" "apisix/apisix" "$CFG/apisix-values.yaml"
[ -n "$SHENYU" ] && step "--- ShenYu 网关 ---" && \
  hlm "shenyu" "shenyu/shenyu" "$CFG/shenyu-values.yaml"

# -- RPC 框架 --
[ -n "$DUBBO" ] && step "--- Dubbo-Admin ---" && \
  kube_apply "$CFG/manifests/dubbo-admin.yaml"

# -- 分布式事务 --
[ -n "$SEATA" ] && step "--- Seata ---" && \
  kube_apply "$CFG/manifests/seata.yaml"

# -- 分布式调度 --
[ -n "$XXL_JOB" ] && step "--- XXL-JOB ---" && {
  if [ -z "$DRY_RUN" ]; then
    MYSQL_POD=$(kubectl get pod -n "$NAMESPACE" -l "app.kubernetes.io/component=primary" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    if [ -n "$MYSQL_POD" ]; then
      kubectl exec -i -n "$NAMESPACE" "$MYSQL_POD" -- mysql -uroot -pmysqlroot123 < "$CFG/manifests/xxl-job-init.sql" 2>/dev/null || true
    fi
  fi
  kube_apply "$CFG/manifests/xxl-job.yaml"
}

# -- 监控 --
[ -n "$PROMETHEUS" ] && step "--- Prometheus + Grafana ---" && \
  hlm "prometheus" "prometheus-community/kube-prometheus-stack" "$CFG/prometheus-values.yaml"

# -- 日志 --
if [ -n "$LOKI" ]; then
  step "--- Loki HA + Grafana Alloy ---"
  hlm "loki" "grafana-community/loki" "$CFG/loki-values.yaml" --timeout 15m
  hlm "alloy" "grafana/alloy" "$CFG/alloy-values.yaml"
fi

# -- 备份 / 依赖更新 --
[ -n "$VELERO" ] && step "--- Velero ---" && \
  hlm "velero" "vmware-tanzu/velero" "$CFG/velero-values.yaml" --timeout 15m
[ -n "$RENOVATE" ] && step "--- Renovate CronJob ---" && \
  hlm "renovate" "oci://ghcr.io/renovatebot/charts/renovate" "$CFG/renovate-values.yaml"

# -- 消息队列 --
[ -n "$PULSAR" ] && step "--- Pulsar ---" && \
  hlm "pulsar" "apachepulsar/pulsar" "$CFG/pulsar-values.yaml" "--timeout 15m"

# -- 流计算 --
[ -n "$FLINK" ] && step "--- Flink ---" && \
  kube_apply "$CFG/manifests/flink.yaml"

# -- CI/CD --
[ -n "$JENKINS" ] && step "--- Jenkins ---" && \
  hlm "jenkins" "jenkins/jenkins" "$CFG/jenkins-values.yaml"

# -- 应用监控 --
[ -n "$SBA" ] && step "--- Spring Boot Admin ---" && \
  kube_apply "$CFG/manifests/spring-boot-admin.yaml"

# -- 镜像库 --
if [ -n "$HARBOR" ]; then
  step "--- Harbor ---"
  HARBOR_EXTRA=()
  [ -n "$WITH_INGRESS" ] && HARBOR_EXTRA+=(--set "expose.type=ingress" --set "expose.ingress.hosts.core=$INGRESS_DOMAIN")
  [ -n "$MINIO" ] && HARBOR_EXTRA+=(
    --set "persistence.imageChartStorage.type=s3"
    --set "persistence.imageChartStorage.s3.region=us-east-1"
    --set "persistence.imageChartStorage.s3.bucket=harbor"
    --set "persistence.imageChartStorage.s3.accesskey=minioadmin"
    --set "persistence.imageChartStorage.s3.secretkey=minioadmin"
    --set "persistence.imageChartStorage.s3.endpoint=http://minio.$NAMESPACE.svc:9000"
    --set "persistence.imageChartStorage.s3.secure=false"
  )
  hlm "harbor" "harbor/harbor" "$CFG/harbor-values.yaml" \
    "--set harborAdminPassword=$ADMIN_PASS" "${HARBOR_EXTRA[@]}"
fi

# ══════════════════════════════════
# 摘要
# ══════════════════════════════════
step "===== 部署摘要 ====="
if [ -n "$DRY_RUN" ]; then
  NODE_IP="localhost"
else
  NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null || echo "localhost")
fi
echo ""
[ -n "$PG" ]  && echo "  PostgreSQL : pg-postgresql-ha-pgpool.$NAMESPACE.svc:5432 (harbor / harbordb123)"
[ -n "$MYSQL" ] && echo "  MySQL      : mysql-mysql-primary.$NAMESPACE.svc:3306 (root / mysqlroot123)"
[ -n "$REDIS" ] && echo "  Redis      : redis-redis.$NAMESPACE.svc:6379 (redispass123)"
[ -n "$MINIO" ] && echo "  MinIO      : minio.$NAMESPACE.svc:9000 (minioadmin / minioadmin)"
[ -n "$ES" ]    && echo "  ES         : elasticsearch-master.$NAMESPACE.svc:9200"
[ -n "$MONGO" ] && echo "  MongoDB    : mongodb.$NAMESPACE.svc:27017 (root / mongoroot123)"
[ -n "$ZK" ]    && echo "  ZooKeeper  : zookeeper.$NAMESPACE.svc:2181"
[ -n "$ETCD" ]  && echo "  etcd       : etcd.$NAMESPACE.svc:2379 (root / etcdroot123)"
[ -n "$KAFKA" ] && echo "  Kafka      : kafka-kafka-bootstrap.$NAMESPACE.svc:9092"
[ -n "$ROCKETMQ" ] && echo "  RocketMQ NS: rocketmq-namesrv.$NAMESPACE.svc:9876"
[ -n "$NACOS" ] && echo "  Nacos      : nacos.$NAMESPACE.svc:8848 (nacos / nacos)"
[ -n "$APOLLO" ] && echo "  Apollo     : apollo-apollo-portal.$NAMESPACE.svc:8070 (apollo / admin)"
[ -n "$SENTINEL" ] && echo "  Sentinel   : sentinel-dashboard.$NAMESPACE.svc:8080 (sentinel / sentinel123)"
[ -n "$SKYWALKING" ] && echo "  SkyWalking : skywalking-oap.$NAMESPACE.svc:11800"
[ -n "$OPENBAO" ] && echo "  OpenBao    : openbao.$NAMESPACE.svc:8200 (等待 init/unseal)"
[ -n "$CERT_MANAGER" ] && echo "  cert-manager: controllers + CRDs (no Issuer/Certificate created)"
[ -n "$ARGOCD" ] && echo "  Argo CD    : https://${NODE_IP}:30013 (admin / initial password secret)"
[ -n "$KYVERNO" ] && echo "  Kyverno    : admission/background/cleanup/reports controllers"
[ -n "$TDENGINE" ] && echo "  TDengine   : tdengine.$NAMESPACE.svc:6030 (root / taosdata)"
[ -n "$SHARDINGSPHERE" ] && echo "  ShardingSphere : shardingsphere-proxy.$NAMESPACE.svc:3307 (MySQL协议)"
[ -n "$APISIX" ] && echo "  APISIX     : http://${NODE_IP}:30011"
[ -n "$SHENYU" ]  && echo "  ShenYu     : shenyu-admin.$NAMESPACE.svc:31095 (admin / 123456)"
[ -n "$DUBBO" ]   && echo "  Dubbo-Admin: dubbo-admin.$NAMESPACE.svc:8081 (root / root)"
[ -n "$SEATA" ]   && echo "  Seata      : seata-server.$NAMESPACE.svc:8091 (file模式)"
[ -n "$XXL_JOB" ] && echo "  XXL-JOB    : xxl-job-admin.$NAMESPACE.svc:8080 (admin / 123456)"
[ -n "$PROMETHEUS" ] && echo "  Prometheus : prometheus-operated.$NAMESPACE.svc:9090"
[ -n "$LOKI" ]    && echo "  Loki       : loki-gateway.$NAMESPACE.svc:80 (Alloy 2 replicas)"
[ -n "$VELERO" ]  && echo "  Velero     : controller + node-agent (尚未创建备份计划)"
[ -n "$RENOVATE" ] && echo "  Renovate   : suspended CronJob (等待 Secret 后启用)"
[ -n "$PULSAR" ]  && echo "  Pulsar     : pulsar-broker.$NAMESPACE.svc:6650"
[ -n "$FLINK" ]   && echo "  Flink      : flink-jobmanager.$NAMESPACE.svc:8081"
[ -n "$JENKINS" ] && echo "  Jenkins    : jenkins.$NAMESPACE.svc:8080 (admin / admin123)"
[ -n "$SBA" ]     && echo "  Spring Boot Admin: spring-boot-admin.$NAMESPACE.svc:8080"
[ -n "$HARBOR" ] && {
  [ -n "$WITH_INGRESS" ] && echo "  Harbor     : http://$INGRESS_DOMAIN (admin / $ADMIN_PASS)" \
    || echo "  Harbor     : http://${NODE_IP}:30002 (admin / $ADMIN_PASS)"
}

echo ""
[ -z "$DRY_RUN" ] && kubectl get pods -n "$NAMESPACE" --ignore-not-found 2>/dev/null
[ -n "$DRY_RUN" ] && echo -e "\n${CYAN}[DRY-RUN] 未执行实际部署${NC}"
exit 0
