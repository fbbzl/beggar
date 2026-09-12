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

首版支持全新安装的 **Ubuntu Desktop 24.04 LTS / 带图形桌面的 Debian 13，x86_64**，需要 systemd 和 `/dev/kvm` 读写权限。将本仓库完整复制或解压到已安装的系统后，在登录用户的桌面终端里进入仓库目录，执行 `bash bootstrap-linux.sh`。基座会从官方源安装 Rancher Desktop，用 Moby 作为容器引擎，并关闭内置 Kubernetes，同时安装 k3d；安装详情、重跑与验证边界见 [Linux 安装说明](docs/linux-bootstrap.md)。

```bash
# 先预览完整流程
bash bootstrap-linux.sh --dry-run

# 只安装基座
bash bootstrap-linux.sh --base-only

# 从空白系统安装基座并创建 3 节点开发集群
bash bootstrap-linux.sh

# 在上述集群上增加一个组件，先观察效果
bash bootstrap-linux.sh --minio

# 明确需要全量时执行（资源需求取决于所选组件）
bash bootstrap-linux.sh --all

# 后续直接使用中间件脚本时，显式选择项目集群
KUBECONFIG="$HOME/.kube/beggar-cluster.yaml" bash deploy-registry-stack.sh --minio

# 交互式安装：空白 ECS 或已有集群都能用
bash install-ecs-stack.sh
```

交互安装器会在选择组件后询问版本策略。直接输入 `y` 使用仓库内的 2026-06 默认稳定版本；输入 `n` 可一次性覆盖，例如：

```text
是否使用默认版本？输入 y 使用默认版本，输入 n 指定版本 [y]: n
输入版本覆盖（组件=版本；Helm 覆盖 Chart，原生清单覆盖镜像标签；逗号分隔） []: mysql=14.0.3,redis=28.0.15,flink=1.20.2
```

非交互执行可使用同一套覆盖参数：

```bash
BEGGAR_VERSION_OVERRIDES=mysql=14.0.3,redis=28.0.15,flink=1.20.2 \
  bash deploy-registry-stack.sh --mysql --redis
```

默认版本清单位于 `config/versions.env`。MySQL 默认选择 8.4 对应的 Bitnami Chart `12.3.5`；需要 MySQL 9.4 时可覆盖为 Chart `14.0.3`。版本覆盖只接受安全的版本字符，未知组件、重复组件和非法值会在部署前拒绝。纯原生清单可直接使用 `flink=1.20.2`，也支持 `image-flink=1.20.2`；与 Helm 组件同名的原生镜像使用 `image-mysql=8.4`、`image-redis=7.4` 或 `image-minio=RELEASE.2025-07-23T15-54-02Z`，可与对应的 Chart 覆盖同时传入。

Nacos 和 TDengine 都可通过交互安装器一键部署。Nacos 使用官方 `nacos-k8s v1.0.2`，会自动初始化 MySQL schema；TDengine 使用官方 `TDengine-Operator` 的 `tdengine-3.5.0.tgz`。首次部署时脚本会下载固定版本 Chart 到本机缓存，随后执行 Helm 安装。

以下为**已具备工具链和目标集群 kubeconfig**时的独立入口：

```bash

# 按需组合
bash deploy-registry-stack.sh --mysql --redis --kafka --nacos

# 一条命令启动最小高可用 APISIX（2 网关 + 3 etcd，需要至少 3 个节点）
bash deploy-registry-stack.sh --apisix

# 一条命令补齐研发平台工具（cert-manager/Argo CD/Kyverno/etcd/OpenBao/Loki/Velero/Renovate）
bash deploy-registry-stack.sh --platform-all

# 生产环境：3 台物理机 K3s HA
NODE_IPS=10.0.0.1,10.0.0.2,10.0.0.3 bash deploy-k8s-cluster.sh k3s
export KUBECONFIG="$HOME/.kube/config-beggar"
bash deploy-registry-stack.sh --all

# 先校验不部署
DRY_RUN=1 bash deploy-registry-stack.sh --all
```

### 🪟 Windows

Windows 基座安装将在 Linux 效果确认后补齐；以下命令仍要求已有基础环境。

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
│  cert-manager  Argo CD  Kyverno  OpenBao(3)  Loki+Alloy      │
│                                                               │
│  🛡 HA 组件使用 PDB / 反亲和；例外见“平台工具说明”             │
└──────────────────────────────────────────────────────────────┘
```

---

## 📦 组件列表

| # | 中间件 | Linux 参数 | Windows 参数 | 节点数 | 镜像来源 | 说明 |
|---|--------|-----------|-------------|--------|---------|------|
| 1 | 🐬 **MySQL** | `--mysql` | `-Mysql` | 3 | Bitnami Chart `12.3.5` / MySQL `8.4` | 一主二从、半同步复制 |
| 2 | 🐘 **PostgreSQL** | `--pg` | `-Pg` | 3 | 官方 `postgres:16` | 流复制、hot standby |
| 3 | 🧩 **Redis** | `--redis` | `-Redis` | 3 | Bitnami Chart `27.0.13` / Redis `8.8` | Sentinel 高可用 |
| 4 | 📦 **MinIO** | `--minio` | `-MinIO` | 1 | 官方 `minio/minio` | S3 对象存储 |
| 5 | 📡 **Kafka** | `--kafka` | `-Kafka` | 3 | Bitnami | KRaft 模式、无 ZooKeeper |
| 6 | 🔍 **Elasticsearch** | `--es` | `-Es` | 3 | Elastic | 搜索 + 日志集群 |
| 7 | 🍃 **MongoDB** | `--mongo` | `-Mongo` | 3 | Bitnami | ReplicaSet 副本集 |
| 8 | 🦎 **ZooKeeper** | `--zk` | `-Zk` | 3 | Bitnami | 分布式协调服务 |
| 9 | 🌐 **Nacos** | `--nacos` | `-Nacos` | 3 | Nacos 官方 Chart | 服务注册与配置中心（自动初始化 MySQL） |
| 10 | 🚀 **RocketMQ** | `--rocketmq` | `-RocketMQ` | 6 | Apache | 3 NameServer + 3 Broker |
| 11 | ⚡ **Sentinel** | `--sentinel` | `-Sentinel` | 2 | Sentinel 官方 | 流量治理可视化控制台 |
| 12 | 📈 **SkyWalking** | `--skywalking` | `-Skywalking` | 3 | Apache | 分布式链路追踪 APM |
| 13 | ⚙️ **Apollo** | `--apollo` | `-Apollo` | 3 | Apollo 官方 | 分布式配置中心 |
| 14 | ⏱ **TDengine** | `--tdengine` | `-Tdengine` | 3 | TDengine 官方 Chart | 时序数据库三节点集群 |
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
| 27 | 🪪 **cert-manager** | `--cert-manager` | `-CertManager` | 2+3+2 | Jetstack | 证书生命周期控制器与 CRD；默认不创建 Issuer |
| 28 | 🚢 **Argo CD** | `--argocd` | `-ArgoCD` | 2+2+2+HA Redis | Argo Project | GitOps 持续交付控制平面 |
| 29 | 🛡️ **Kyverno** | `--kyverno` | `-Kyverno` | 3+2+2+2 | Kyverno | 策略准入与报告控制平面；默认不安装策略 |
| 30 | 🧱 **独立 etcd** | `--etcd` | `-Etcd` | 3 | Bitnami/etcd | 独立协调与键值存储，不与 APISIX 共用 |
| 31 | 🔐 **OpenBao** | `--openbao` | `-OpenBao` | 3 | OpenBao | Raft 密钥管理，需手动 init/unseal |
| 32 | 🪵 **Loki + Alloy** | `--loki` | `-Loki` | 3+3+3+2+2 | Grafana | HA 日志存储与集群化采集（依赖 MinIO/S3） |
| 33 | 💾 **Velero** | `--velero` | `-Velero` | 1+DaemonSet | Velero | K8s 备份控制器与节点代理（依赖 MinIO/S3） |
| 34 | 🤖 **Renovate** | `--renovate` | `-Renovate` | CronJob | Renovate | 依赖自动更新，默认暂停 |
| 35 | 🧰 **平台工具** | `--platform-all` | `-PlatformAll` | - | - | 部署第 27～34 项；不改变 `--all` |
| 36 | 🎯 **全部** | `--all` | `-WithAll` | - | - | 部署原有中间件集合 |

> 💡 `--loki` 和 `--velero` 会自动部署 MinIO 依赖；`--platform-all` 只包含平台工具，不会扩大原有 `--all` 的范围。

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
| `30012` | Argo CD HTTP service port | 转发到 Argo CD server |
| `30013` | Argo CD HTTPS | GitOps UI/API TLS 入口 |
| `30307` | ShardingSphere-Proxy | 多主分库 MySQL 协议入口 |

---

## 📁 配置说明

```
beggar/
├── deploy-k8s-cluster.sh             # 🐧 Linux：K3s 集群部署
├── deploy-k8s-cluster.ps1            # 🪟 Windows：K3s 集群部署
├── install-ecs-stack.sh               # 🐧 Linux：ECS + 中间件交互式安装器
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
    ├── cert-manager-values.yaml      # cert-manager HA 控制平面
    ├── argocd-values.yaml            # Argo CD GitOps 控制平面
    ├── kyverno-values.yaml           # Kyverno 策略控制平面
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

以下命令一次安装平台工具集合；Loki 和 Velero 会自动带上同命名空间的 MinIO：

```bash
bash deploy-registry-stack.sh --platform-all
# Windows: .\deploy-registry-stack.ps1 -PlatformAll
```

独立 etcd 使用 3 个副本、硬反亲和和 `minAvailable: 2` 的 PDB，地址是 `etcd.registry-stack.svc:2379`。它不会替代 APISIX 自带的 etcd。仓库内密码仅用于本地/演示环境，共享环境必须先修改 `config/etcd-values.yaml`。

cert-manager 只安装控制器和 CRD。不同环境所需的 `Issuer`、`ClusterIssuer` 和 `Certificate` 资源需要单独创建。

Argo CD 通过 `https://<NodeIP>:30013` 暴露 NodePort。初始 admin 密码仍在 chart 创建的 Secret 中，离开受信网络前必须轮换。

Kyverno 只安装 admission、background、cleanup 和 reports 控制器。默认不安装策略包，只有添加策略后才开始执行约束。

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
