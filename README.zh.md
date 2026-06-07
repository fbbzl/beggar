<div align="center">
  <h1>🐱 Beggar</h1>
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
│  Elasticsearch(3)  MongoDB(3)  ZooKeeper(3)                  │
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
│  时序数据库 ─────────────────────────────────────────────   │
│  TDengine(3)                                                 │
│                                                               │
│  镜像仓库 ────────────────────────────────────────────────   │
│  Harbor (Harbor 镜像库)                                      │
│                                                               │
│  🛡 所有中间件 ≥ 3 节点 · 自动防脑裂                          │
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
| 17 | 🎯 **全部** | `--all` | `-WithAll` | - | - | 一键全量部署 |

> 💡 MySQL、PostgreSQL、Redis、MinIO 使用**官方镜像**，无 Bitnami 拉取限制，国内用户友好。

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
    │   └── shardingsphere.yaml             # ShardingSphere 多主分库
    ├── harbor-values.yaml            # Harbor Helm 配置
    ├── kafka-values.yaml             # Kafka KRaft 配置
    ├── elasticsearch-values.yaml     # Elasticsearch 配置
    ├── nacos-values.yaml             # Nacos 配置（依赖 MySQL）
    ├── mongodb-values.yaml           # MongoDB 配置
    ├── zookeeper-values.yaml         # ZooKeeper 配置
    ├── skywalking-values.yaml        # SkyWalking 配置（依赖 ES）
    ├── apollo-values.yaml            # Apollo 配置（依赖 MySQL）
    └── tdengine-values.yaml          # TDengine 配置
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
