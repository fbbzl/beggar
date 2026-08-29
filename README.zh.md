<div align="center">
  <img src="icon.svg" width="64" height="64" alt="Beggar logo" />
  <h1>Beggar</h1>
  <p><strong>从裸机到中间件全家桶 · 一行命令全搞定</strong></p>
  <p>
    <img src="https://img.shields.io/badge/Linux-%23FCC624?style=flat-square&logo=linux&logoColor=black" />
    <img src="https://img.shields.io/badge/Windows-%230078D4?style=flat-square&logo=windows&logoColor=white" />
    <img src="https://img.shields.io/badge/K3s-%23FFC61C?style=flat-square&logo=k3s&logoColor=black" />
    <img src="https://img.shields.io/badge/Helm-%230F1689?style=flat-square&logo=helm&logoColor=white" />
    <img src="https://img.shields.io/badge/license-MIT-green?style=flat-square" />
  </p>
  <p>
    <a href="#-快速开始">快速开始</a> •
    <a href="#-架构">架构</a> •
    <a href="#-组件列表">组件列表</a> •
    <a href="#-配置说明">配置说明</a>
  </p>
  <br/>
</div>

---

## 🚀 快速开始

### 🐧 Linux

```bash
# 一行起飞（3 节点本地集群 + 全量中间件）
bash deploy-k8s-cluster.sh k3d && bash deploy-registry-stack.sh --all

# 按需组合
bash deploy-registry-stack.sh --mysql --redis --kafka --nacos

# 一条命令启动最小高可用 APISIX（2 网关 + 3 etcd，需要至少 3 个节点）
bash deploy-registry-stack.sh --apisix

# 一条命令补齐研发平台工具（etcd/OpenBao/Loki/Velero/Renovate）
bash deploy-registry-stack.sh --platform-all

# 生产环境：3 台物理机 K3s HA
NODE_IPS=10.0.0.1,10.0.0.2,10.0.0.3 bash deploy-k8s-cluster.sh k3s
bash deploy-registry-stack.sh --all

# 先校验不部署
DRY_RUN=1 bash deploy-registry-stack.sh --all
```

### 🪟 Windows

```powershell
# 本地集群 + 全量
.\deploy-k8s-cluster.ps1 -WithK3d
.\deploy-registry-stack.ps1 -WithAll

# 按需组合
.\deploy-registry-stack.ps1 -Mysql -Redis -Kafka -Nacos

# 一条命令启动最小高可用 APISIX（2 网关 + 3 etcd，需要至少 3 个节点）
.\deploy-registry-stack.ps1 -Apisix

# 一条命令补齐研发平台工具
.\deploy-registry-stack.ps1 -PlatformAll

# 先校验
.\deploy-registry-stack.ps1 -DryRun -WithAll
```

---

## 🏗 架构

```
┌──────────────────────────────────────────────────────────────┐
│                    deploy-k8s-cluster.sh/.ps1                  │
│                K3s / k3d · 3 节点 HA · Embedded etcd          │
├──────────────────────────────────────────────────────────────┤
│                    deploy-registry-stack.sh/.ps1               │
├──────────────────────────────────────────────────────────────┤
│                                                               │
│  基础层 ──────────────────────────────────────────────────   │
│  PostgreSQL(3)    MySQL(3)    Redis(3)    MinIO              │
│                                                               │
│  存储 & 协调 ─────────────────────────────────────────────   │
│  Elasticsearch(3)  MongoDB(3)  ZooKeeper(3)  etcd(3)         │
│                                                               │
│  消息队列 ────────────────────────────────────────────────   │
│  Kafka KRaft(3)    RocketMQ(3NS + 3Broker)                   │
│                                                               │
│  注册 & 配置 ─────────────────────────────────────────────   │
│  Nacos(3)    Apollo(3)    ShardingSphere 多主分库(2)         │
│                                                               │
│  流量治理 & APM ──────────────────────────────────────────   │
│  Sentinel Dashboard(2)    SkyWalking OAP(3)                  │
│                                                               │
│  API 网关 ─────────────────────────────────────────────────  │
│  APISIX HA(2 + etcd 3)    ShenYu(2 admin + 2 bootstrap)       │
│                                                               │
│  时序数据库 ─────────────────────────────────────────────   │
│  TDengine(3)                                                 │
│                                                               │
│  镜像仓库 ────────────────────────────────────────────────   │
│  Harbor (Harbor 镜像库)                                      │
│                                                               │
│  平台工程 ────────────────────────────────────────────────   │
│  OpenBao(3)  Loki HA + Alloy(2)  Velero  Renovate CronJob    │
│                                                               │
│  🛡 HA 组件使用 PDB / 反亲和；例外见“平台工具说明”             │
└──────────────────────────────────────────────────────────────┘
```

---

## 📦 组件列表

| # | 中间件 | Linux 参数 | Windows 参数 | 节点数 | 镜像来源 | 说明 |
|---|--------|-----------|-------------|--------|---------|------|
| 1 | 🐬 **MySQL** | `--mysql` | `-Mysql` | 3 | 官方 `mysql:8.0` | 一主二从、半同步复制 |
| 2 | 🐘 **PostgreSQL** | `--pg` | `-Pg` | 3 | 官方 `postgres:16` | 流复制、hot standby |
| 3 | 🧩 **Redis** | `--redis` | `-Redis` | 3 | 官方 `redis:7` | Sentinel 高可用 |
| 4 | 📦 **MinIO** | `--minio` | `-MinIO` | 1 | 官方 `minio/minio` | S3 对象存储 |
| 5 | 📡 **Kafka** | `--kafka` | `-Kafka` | 3 | Bitnami | KRaft 模式、无 ZooKeeper |
| 6 | 🔍 **Elasticsearch** | `--es` | `-Es` | 3 | Elastic | 搜索 + 日志集群 |
| 7 | 🍃 **MongoDB** | `--mongo` | `-Mongo` | 3 | Bitnami | ReplicaSet 副本集 |
| 8 | 🦎 **ZooKeeper** | `--zk` | `-Zk` | 3 | Bitnami | 分布式协调服务 |
| 9 | 🌐 **Nacos** | `--nacos` | `-Nacos` | 3 | Nacos 官方 | 注册中心 + 配置中心 |
| 10 | 🚀 **RocketMQ** | `--rocketmq` | `-RocketMQ` | 6 | Apache | 3 NameServer + 3 Broker |
| 11 | ⚡ **Sentinel** | `--sentinel` | `-Sentinel` | 2 | Sentinel 官方 | 流量治理可视化控制台 |
| 12 | 📈 **SkyWalking** | `--skywalking` | `-Skywalking` | 3 | Apache | 分布式链路追踪 APM |
| 13 | ⚙️ **Apollo** | `--apollo` | `-Apollo` | 3 | Apollo 官方 | 分布式配置中心 |
| 14 | ⏱ **TDengine** | `--tdengine` | `-Tdengine` | 3 | TDengine | 时序数据库 |
| 15 | 🔀 **ShardingSphere** | `--shardingsphere` | `-Shardingsphere` | 2 | Apache | MySQL 多主分库 |
| 16 | 🏛 **Harbor** | `--harbor` | `-Harbor` | - | Harbor CNCF | 企业级镜像仓库 |
| 17 | 🛣️ **APISIX HA** | `--apisix` | `-Apisix` | 2+3 | Apache | 最小高可用 API 网关 + etcd |
| 18 | 🔗 **ShenYu** | `--shenyu` | `-Shenyu` | 2+2 | Apache | API 网关 + 管理控制台 |
| 19 | 🔌 **Dubbo** | `--dubbo` | `-Dubbo` | 2 | Apache | RPC 框架管理端（依赖 ZK） |
| 20 | 📋 **Seata** | `--seata` | `-Seata` | 2 | Apache | 分布式事务（file 模式） |
| 21 | ⏰ **XXL-JOB** | `--xxl-job` | `-XxlJob` | 2 | xuxueli | 分布式调度中心（依赖 MySQL） |
| 22 | 📊 **Prometheus+Grafana** | `--prometheus` | `-Prometheus` | 1+1 | Prometheus/Grafana | 监控告警栈 |
| 23 | 💬 **Pulsar** | `--pulsar` | `-Pulsar` | 3+1 | Apache | 云原生消息队列 |
| 24 | 🌊 **Flink** | `--flink` | `-Flink` | 1+2 | Apache | 流计算引擎 |
| 25 | 🏗️ **Jenkins** | `--jenkins` | `-Jenkins` | 1 | Jenkins | CI/CD 持续集成 |
| 26 | 🟢 **Spring Boot Admin** | `--spring-boot-admin` | `-Sba` | 2 | codecentric | Spring Boot 应用监控 |
| 27 | 🧱 **独立 etcd** | `--etcd` | `-Etcd` | 3 | Bitnami/etcd | 独立协调与键值存储，不与 APISIX 共用 |
| 28 | 🔐 **OpenBao** | `--openbao` | `-OpenBao` | 3 | OpenBao | Raft 密钥管理，需手动 init/unseal |
| 29 | 🪵 **Loki + Alloy** | `--loki` | `-Loki` | 3+3+3+2+2 | Grafana | HA 日志存储与集群化采集（依赖 MinIO/S3） |
| 30 | 💾 **Velero** | `--velero` | `-Velero` | 1+DaemonSet | Velero | K8s 备份控制器与节点代理（依赖 MinIO/S3） |
| 31 | 🤖 **Renovate** | `--renovate` | `-Renovate` | CronJob | Renovate | 依赖自动更新，默认暂停 |
| 32 | 🧰 **平台工具** | `--platform-all` | `-PlatformAll` | - | - | 部署第 27～31 项；不改变 `--all` |
| 33 | 🎯 **全部** | `--all` | `-WithAll` | - | - | 部署原有中间件集合 |

> 💡 `--loki` 和 `--velero` 会自动部署 MinIO 依赖；`--platform-all` 只包含新增的平台工具，不会扩大原有 `--all` 的范围。

---

## 🔌 端口映射（NodePort 模式）

| NodePort | 服务 | 说明 |
|----------|------|------|
| `30002` | Harbor HTTP | 镜像库 Web 控制台 |
| `30003` | Harbor HTTPS | 镜像库安全端口 |
| `30006` | SkyWalking UI | 链路追踪前端 |
| `30007` | Apollo Portal | 配置中心管理端 |
| `30008` | Sentinel Dashboard | 流量治理控制台 |
| `30009` | Sentinel API | 监控数据 API |
| `30010` | RocketMQ NameServer | 消息队列客户端接入 |
| `30011` | APISIX HTTP | API 网关入口 |
| `30307` | ShardingSphere-Proxy | 多主分库 MySQL 协议入口 |

---

## 📁 配置说明

```
beggar/
├── deploy-k8s-cluster.sh             # 🐧 Linux：K3s 集群部署
├── deploy-k8s-cluster.ps1            # 🪟 Windows：K3s 集群部署
├── deploy-registry-stack.sh          # 🐧 Linux：中间件一键部署
├── deploy-registry-stack.ps1         # 🪟 Windows：中间件一键部署
└── config/
    ├── manifests/                    # 📜 原生 Kubernetes YAML（零依赖）
    │   ├── mysql-replication.yaml          # MySQL 一主二从
    │   ├── postgresql-ha.yaml              # PostgreSQL 流复制
    │   ├── redis-sentinel.yaml             # Redis Sentinel 高可用
    │   ├── minio.yaml                      # MinIO 对象存储
    │   ├── rocketmq.yaml                   # RocketMQ 3+3
    │   ├── sentinel-dashboard.yaml         # Sentinel 控制台
    │   ├── shardingsphere.yaml             # ShardingSphere 多主分库
    │   ├── dubbo-admin.yaml               # Dubbo-Admin（依赖 ZK）
    │   ├── seata.yaml                     # Seata 分布式事务
    │   ├── xxl-job.yaml                   # XXL-JOB 调度中心
    │   ├── xxl-job-init.sql               # XXL-JOB 初始化 SQL
    │   ├── flink.yaml                     # Flink 会话集群
    │   └── spring-boot-admin.yaml         # Spring Boot 监控
    ├── harbor-values.yaml            # Harbor Helm 配置
    ├── kafka-values.yaml             # Kafka KRaft 配置
    ├── elasticsearch-values.yaml     # Elasticsearch 配置
    ├── nacos-values.yaml             # Nacos 配置（依赖 MySQL）
    ├── mongodb-values.yaml           # MongoDB 配置
    ├── zookeeper-values.yaml         # ZooKeeper 配置
    ├── etcd-values.yaml              # 独立 etcd 3 节点配置
    ├── minio-values.yaml             # MinIO 及共享桶配置
    ├── skywalking-values.yaml        # SkyWalking 配置（依赖 ES）
    ├── apollo-values.yaml            # Apollo 配置（依赖 MySQL）
    ├── tdengine-values.yaml          # TDengine 配置
    ├── apisix-values.yaml            # APISIX 网关配置
    ├── openbao-values.yaml           # OpenBao 3 节点 Raft 配置
    ├── loki-values.yaml              # Loki SimpleScalable HA 配置
    ├── alloy-values.yaml             # Alloy 双副本集群采集配置
    ├── velero-values.yaml            # Velero + MinIO/S3 配置
    ├── renovate-values.yaml          # Renovate 暂停 CronJob 配置
    ├── shenyu-values.yaml            # ShenYu 网关配置
    ├── prometheus-values.yaml        # Prometheus+Grafana 配置
    ├── pulsar-values.yaml            # Pulsar 消息队列配置
    └── jenkins-values.yaml           # Jenkins CI/CD 配置
```

## 🛣️ APISIX 使用说明

APISIX HA 与其他 Helm 中间件一样，通过 Rancher Desktop 提供的 `helm` / `kubectl` 部署；一条 `-Apisix` 命令会启动 2 个 APISIX 和 3 个 etcd。HTTP 入口为 `http://<NodeIP>:30011`；Admin API 保持 ClusterIP，仅供集群内使用。硬反亲和规则会将网关和 etcd 副本分别分散到不同节点，因此集群少于 3 个可调度节点时不会部署成功。该配置不启用 Ingress Controller；路由通过 Admin API 配置。`--all` 会同时安装 APISIX HA 和 ShenYu，但同一个外部域名/入口应只交由其中一个网关处理。

## 🧰 平台工具说明

以下命令一次安装五项平台工具；Loki 和 Velero 会自动带上同命名空间的 MinIO：

```bash
bash deploy-registry-stack.sh --platform-all
# Windows: .\deploy-registry-stack.ps1 -PlatformAll
```

独立 etcd 使用 3 个副本、硬反亲和和 `minAvailable: 2` 的 PDB，地址是 `etcd.registry-stack.svc:2379`。它不会替代 APISIX 自带的 etcd。仓库内密码仅用于本地/演示环境，共享环境必须先修改 `config/etcd-values.yaml`。

OpenBao 部署后会保持未初始化、密封状态，这是预期的安全行为。保存好下面第一条命令输出的恢复密钥和 root token，再初始化一个节点、让另外两个节点加入 Raft 并分别解封：

```bash
kubectl exec -n registry-stack openbao-0 -- bao operator init -key-shares=3 -key-threshold=2
kubectl exec -n registry-stack openbao-0 -- bao operator unseal '<KEY_1>'
kubectl exec -n registry-stack openbao-0 -- bao operator unseal '<KEY_2>'

kubectl exec -n registry-stack openbao-1 -- bao operator raft join http://openbao-0.openbao-internal:8200
kubectl exec -n registry-stack openbao-1 -- bao operator unseal '<KEY_1>'
kubectl exec -n registry-stack openbao-1 -- bao operator unseal '<KEY_2>'
kubectl exec -n registry-stack openbao-2 -- bao operator raft join http://openbao-0.openbao-internal:8200
kubectl exec -n registry-stack openbao-2 -- bao operator unseal '<KEY_1>'
kubectl exec -n registry-stack openbao-2 -- bao operator unseal '<KEY_2>'
kubectl exec -n registry-stack openbao-0 -- bao operator raft list-peers
```

Loki 使用 SimpleScalable：write/read/backend 各 3 副本，gateway 和 Alloy 各 2 副本；Alloy clustering 会分片 Pod 日志目标，避免双份采集。默认 MinIO 仍是单副本开发配置，因此这里保证的是 Loki 计算面 HA，不是端到端存储 HA；生产环境应把 `config/loki-values.yaml` 与 `config/velero-values.yaml` 指向外部高可用 S3。

Velero 安装不会自动执行备份或恢复。确认外部对象存储后，可用 Velero CLI 手工创建并验证计划：

```bash
velero schedule create registry-stack-daily --schedule "0 3 * * *" --include-namespaces registry-stack
velero backup get
# 恢复属于破坏性操作，核对备份名和目标集群后再执行：
velero restore create --from-backup '<BACKUP_NAME>'
```

Velero 官方服务端当前固定为单控制器且没有 leader election；本配置没有强行扩容来伪造 HA。Deployment 可在节点故障后重建，node-agent 则覆盖每个节点，但控制器切换期间会有短暂中断。

Renovate 默认是暂停的 CronJob，不会在没有令牌时访问仓库。为 GitHub 创建凭据并显式启用：

```bash
kubectl create secret generic renovate-credentials -n registry-stack \
  --from-literal=RENOVATE_PLATFORM=github \
  --from-literal=RENOVATE_TOKEN='<TOKEN>'
kubectl patch cronjob renovate -n registry-stack --type merge -p '{"spec":{"suspend":false}}'
```

---

## 🧹 卸载

```bash
# 一键清理所有中间件
kubectl delete ns registry-stack

# 清理本地 k3d 集群
k3d cluster delete beggar
```

---

<div align="blank">
  <sub>🇨🇳 专为 Java 中间件生态打造 · 欢迎 Star 和 PR</sub>
</div>
