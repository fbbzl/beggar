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

# ── 全部组件初始 OFF ──
PG=; MYSQL=; REDIS=; MINIO=; KAFKA=; ES=; MONGO=; ZK=;
NACOS=; ROCKETMQ=; SENTINEL=; SKYWALKING=; APOLLO=; TDENGINE=; HARBOR=; SHARDINGSPHERE=
SHENYU=; DUBBO=; SEATA=; XXL_JOB=; PROMETHEUS=; PULSAR=; FLINK=; JENKINS=; SBA=; ALL=

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
    --nacos)            NACOS=1 ;;
    --rocketmq)         ROCKETMQ=1 ;;
    --sentinel)         SENTINEL=1 ;;
    --skywalking)       SKYWALKING=1 ;;
    --apollo)           APOLLO=1 ;;
    --tdengine)         TDENGINE=1 ;;
    --minio)            MINIO=1 ;;
    --harbor)           HARBOR=1 ;;
    --shardingsphere)   SHARDINGSPHERE=1 ;;
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
    --all)              ALL=1 ;;
    --ingress)          WITH_INGRESS=1 ;;
    --domain)           INGRESS_DOMAIN="$2"; shift ;;
    --dry-run)          DRY_RUN=1 ;;
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
      echo "  --nacos             Nacos 3-node (+MySQL)"
      echo "  --rocketmq          RocketMQ 3+3"
      echo "  --sentinel          Sentinel Dashboard 2-node"
      echo "  --skywalking        SkyWalking OAP 3-node"
      echo "  --apollo            Apollo 3-node (+MySQL)"
      echo "  --tdengine          TDengine 3-node"
      echo "  --minio             MinIO 对象存储"
      echo "  --harbor            Harbor 镜像库 (+PG+Redis)"
      echo "  --shardingsphere    ShardingSphere 多主分库 (+3xMySQL)"
      echo "  --shenyu            Apache ShenYu API 网关 (+admin+bootstrap)"
      echo "  --dubbo             Apache Dubbo-Admin (+ZK)"
      echo "  --seata             Apache Seata 分布式事务 (file模式)"
      echo "  --xxl-job           XXL-JOB 分布式调度 (+MySQL)"
      echo "  --prometheus        Prometheus + Grafana 监控栈"
      echo "  --pulsar            Apache Pulsar 消息队列"
      echo "  --flink             Apache Flink 流计算"
      echo "  --jenkins           Jenkins CI/CD"
      echo "  --spring-boot-admin | -sba Spring Boot Admin 应用监控"
      echo "  --all               全部"
      echo "  --ingress           启用 Ingress (默认 NodePort)"
      echo "  --domain <d>        Ingress 域名 (默认 registry.local)"
      echo "  --dry-run           校验配置不实际部署"
      echo ""
      echo "环境变量: NAMESPACE, ADMIN_PASS, DRY_RUN"
      exit 0
      ;;
    *) echo "未知选项: $1 (--help 查看帮助)"; exit 1 ;;
  esac
  shift
done

# ── --all 快捷 ──
[ -n "$ALL" ] && PG=1 MYSQL=1 REDIS=1 MINIO=1 KAFKA=1 ES=1 MONGO=1 ZK=1 \
    NACOS=1 ROCKETMQ=1 SENTINEL=1 SKYWALKING=1 APOLLO=1 TDENGINE=1 HARBOR=1 SHARDINGSPHERE=1 \
    SHENYU=1 DUBBO=1 SEATA=1 XXL_JOB=1 PROMETHEUS=1 PULSAR=1 FLINK=1 JENKINS=1 SBA=1

# ── 依赖自动推导 ──
[ -n "$NACOS" ]   && MYSQL=1    # Nacos 需要 MySQL
[ -n "$APOLLO" ]  && MYSQL=1    # Apollo 需要 MySQL
[ -n "$HARBOR" ]  && PG=1 REDIS=1  # Harbor 需要 PG + Redis
[ -n "$DUBBO" ]   && ZK=1       # Dubbo 需要 ZK 作为注册中心
[ -n "$XXL_JOB" ] && MYSQL=1    # XXL-JOB 需要 MySQL

# ── 无参数 → 显示帮助 ──
if [ -z "$PG$MYSQL$REDIS$MINIO$KAFKA$ES$MONGO$ZK$NACOS$ROCKETMQ$SENTINEL$SKYWALKING$APOLLO$TDENGINE$HARBOR$SHARDINGSPHERE$SHENYU$DUBBO$SEATA$XXL_JOB$PROMETHEUS$PULSAR$FLINK$JENKINS$SBA" ]; then
  echo "请指定要部署的组件，例如: bash $0 --mysql"
  echo "查看全部选项: bash $0 --help"
  exit 1
fi

# ══════════════════════════════════
# 工具函数
# ══════════════════════════════════
hlm() {
  local name=$1 chart=$2 values=$3; shift 3
  if [ -n "$DRY_RUN" ]; then echo -e "  ${GRAY}[DRY-RUN] helm upgrade --install $name $chart${NC}"; return 0; fi
  local args=(upgrade --install "$name" "$chart" --namespace "$NAMESPACE" --wait --timeout 10m)
  [ -n "$values" ] && args+=(--values "$values")
  [ $# -gt 0 ] && args+=("$@")
  local out
  out=$(helm "${args[@]}" 2>&1) || {
    warn "$name 部署异常"; echo "$out" | while IFS= read -r l; do echo -e "    ${GRAY}$l${NC}"; done
    return 1
  }
  ok "$name"; return 0
}

kube_apply() {
  [ -n "$DRY_RUN" ] && echo -e "  ${GRAY}[DRY-RUN] kubectl apply -f $(basename $1)${NC}" && return 0
  local out; out=$(kubectl apply -n "$NAMESPACE" -f "$1" 2>&1) || {
    warn "$(basename $1) 异常"; echo "$out" | while IFS= read -r l; do echo -e "  ${GRAY}$l${NC}"; done
    return 1
  }
  ok "$(basename $1)"
}

exec_pod() {
  local pod; pod=$(kubectl get pod -n "$NAMESPACE" -l "$1" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
  [ -z "$pod" ] && return 1
  kubectl exec -n "$NAMESPACE" "$pod" -- bash -c "$2" &>/dev/null || true
}

# ══════════════════════════════════
# 0. 前提
# ══════════════════════════════════
step "前提检查"
command -v kubectl &>/dev/null || { echo "需要 kubectl" >&2; exit 1; }
command -v helm &>/dev/null   || { echo "需要 helm" >&2; exit 1; }
if [ -z "$DRY_RUN" ]; then
  kubectl cluster-info --request-timeout 5s &>/dev/null || { echo "无法连接 K8s" >&2; exit 1; }
  info "K8s 已连接"
fi

step "添加 Helm Repo"
for r in bitnami:https://charts.bitnami.com/bitnami elastic:https://helm.elastic.co harbor:https://helm.goharbor.io \
         nacos-group:https://nacos-group.github.io/nacos-helm apache:https://apache.jfrog.io/artifactory/skywalking-helm \
         apolloconfig:https://apolloconfig.github.io/apollo-helm tdengine:https://tdengine.github.io/helm-charts \
         shenyu:https://apache.github.io/shenyu-helm-chart \
         prometheus-community:https://prometheus-community.github.io/helm-charts \
         apachepulsar:https://pulsar.apache.org/charts \
         jenkins:https://charts.jenkins.io; do
  helm repo add "${r%%:*}" "${r#*:}" 2>/dev/null || true
done
helm repo update 2>/dev/null || true
ok "Repos 就绪"

step "命名空间: $NAMESPACE"
kubectl create ns "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f - &>/dev/null

# ══════════════════════════════════
# 逐组件部署
# ══════════════════════════════════

# -- 基础存储 --
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
  hlm "minio" "bitnami/minio" "" "--set auth.rootUser=minioadmin,auth.rootPassword=minioadmin --set persistence.size=50Gi --set defaultBuckets=harbor"

# -- 存储 / 协调 --
[ -n "$ES" ]    && step "--- Elasticsearch 3-node ---" && \
  hlm "elasticsearch" "elastic/elasticsearch" "$CFG/elasticsearch-values.yaml"
[ -n "$MONGO" ] && step "--- MongoDB 3-node ---" && \
  hlm "mongodb" "bitnami/mongodb" "$CFG/mongodb-values.yaml"
[ -n "$ZK" ]    && step "--- ZooKeeper 3-node ---" && \
  hlm "zookeeper" "bitnami/zookeeper" "$CFG/zookeeper-values.yaml"

# -- 消息 --
[ -n "$KAFKA" ]    && step "--- Kafka 3-node ---" && \
  hlm "kafka" "bitnami/kafka" "$CFG/kafka-values.yaml"
[ -n "$ROCKETMQ" ] && step "--- RocketMQ ---" && \
  kube_apply "$CFG/manifests/rocketmq.yaml"

# -- 注册 / 配置 --
[ -n "$NACOS" ] && step "--- Nacos 3-node ---" && {
  exec_pod "app.kubernetes.io/component=primary" \
    "mysql -uroot -pmysqlroot123 -e 'CREATE DATABASE IF NOT EXISTS nacos CHARACTER SET utf8mb4;'" || true
  hlm "nacos" "nacos-group/nacos" "$CFG/nacos-values.yaml"
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

# -- 时序 --
[ -n "$TDENGINE" ] && step "--- TDengine 3-node ---" && \
  hlm "tdengine" "tdengine/tdengine" "$CFG/tdengine-values.yaml"

# -- 分库 --
[ -n "$SHARDINGSPHERE" ] && step "--- ShardingSphere-Proxy 多主分库 ---" && \
  kube_apply "$CFG/manifests/shardingsphere.yaml"

# -- API 网关 --
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
  MYSQL_POD=$(kubectl get pod -n "$NAMESPACE" -l "app.kubernetes.io/component=primary" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
  if [ -n "$MYSQL_POD" ]; then
    kubectl exec -i -n "$NAMESPACE" "$MYSQL_POD" -- mysql -uroot -pmysqlroot123 < "$CFG/manifests/xxl-job-init.sql" 2>/dev/null || true
  fi
  kube_apply "$CFG/manifests/xxl-job.yaml"
}

# -- 监控 --
[ -n "$PROMETHEUS" ] && step "--- Prometheus + Grafana ---" && \
  hlm "prometheus" "prometheus-community/kube-prometheus-stack" "$CFG/prometheus-values.yaml"

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
NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null || echo "localhost")
echo ""
[ -n "$PG" ]  && echo "  PostgreSQL : pg-postgresql-ha-pgpool.$NAMESPACE.svc:5432 (harbor / harbordb123)"
[ -n "$MYSQL" ] && echo "  MySQL      : mysql-mysql-primary.$NAMESPACE.svc:3306 (root / mysqlroot123)"
[ -n "$REDIS" ] && echo "  Redis      : redis-redis.$NAMESPACE.svc:6379 (redispass123)"
[ -n "$MINIO" ] && echo "  MinIO      : minio.$NAMESPACE.svc:9000 (minioadmin / minioadmin)"
[ -n "$ES" ]    && echo "  ES         : elasticsearch-master.$NAMESPACE.svc:9200"
[ -n "$MONGO" ] && echo "  MongoDB    : mongodb.$NAMESPACE.svc:27017 (root / mongoroot123)"
[ -n "$ZK" ]    && echo "  ZooKeeper  : zookeeper.$NAMESPACE.svc:2181"
[ -n "$KAFKA" ] && echo "  Kafka      : kafka-kafka-bootstrap.$NAMESPACE.svc:9092"
[ -n "$ROCKETMQ" ] && echo "  RocketMQ NS: rocketmq-namesrv.$NAMESPACE.svc:9876"
[ -n "$NACOS" ] && echo "  Nacos      : nacos.$NAMESPACE.svc:8848 (nacos / nacos)"
[ -n "$APOLLO" ] && echo "  Apollo     : apollo-apollo-portal.$NAMESPACE.svc:8070 (apollo / admin)"
[ -n "$SENTINEL" ] && echo "  Sentinel   : sentinel-dashboard.$NAMESPACE.svc:8080 (sentinel / sentinel123)"
[ -n "$SKYWALKING" ] && echo "  SkyWalking : skywalking-oap.$NAMESPACE.svc:11800"
[ -n "$TDENGINE" ] && echo "  TDengine   : tdengine.$NAMESPACE.svc:6030 (root / taosdata)"
[ -n "$SHARDINGSPHERE" ] && echo "  ShardingSphere : shardingsphere-proxy.$NAMESPACE.svc:3307 (MySQL协议)"
[ -n "$SHENYU" ]  && echo "  ShenYu     : shenyu-admin.$NAMESPACE.svc:31095 (admin / 123456)"
[ -n "$DUBBO" ]   && echo "  Dubbo-Admin: dubbo-admin.$NAMESPACE.svc:8081 (root / root)"
[ -n "$SEATA" ]   && echo "  Seata      : seata-server.$NAMESPACE.svc:8091 (file模式)"
[ -n "$XXL_JOB" ] && echo "  XXL-JOB    : xxl-job-admin.$NAMESPACE.svc:8080 (admin / 123456)"
[ -n "$PROMETHEUS" ] && echo "  Prometheus : prometheus-operated.$NAMESPACE.svc:9090"
[ -n "$PULSAR" ]  && echo "  Pulsar     : pulsar-broker.$NAMESPACE.svc:6650"
[ -n "$FLINK" ]   && echo "  Flink      : flink-jobmanager.$NAMESPACE.svc:8081"
[ -n "$JENKINS" ] && echo "  Jenkins    : jenkins.$NAMESPACE.svc:8080 (admin / admin123)"
[ -n "$SBA" ]     && echo "  Spring Boot Admin: spring-boot-admin.$NAMESPACE.svc:8080"
[ -n "$HARBOR" ] && {
  [ -n "$WITH_INGRESS" ] && echo "  Harbor     : http://$INGRESS_DOMAIN (admin / $ADMIN_PASS)" \
    || echo "  Harbor     : http://${NODE_IP}:30002 (admin / $ADMIN_PASS)"
}

echo ""
kubectl get pods -n "$NAMESPACE" --ignore-not-found 2>/dev/null
[ -n "$DRY_RUN" ] && echo -e "\n${CYAN}[DRY-RUN] 未执行实际部署${NC}"
