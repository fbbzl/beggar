<div align="center">
  <h1>🐱 Beggar</h1>
  <p><strong>从裸机到中间件全家桶 · 一键部署</strong></p>
  <p>
    <img src="https://img.shields.io/badge/Linux-%23FCC624?style=flat-square&logo=linux&logoColor=black" />
    <img src="https://img.shields.io/badge/Windows-%230078D4?style=flat-square&logo=windows&logoColor=white" />
    <img src="https://img.shields.io/badge/K3s-%23FFC61C?style=flat-square&logo=k3s&logoColor=black" />
    <img src="https://img.shields.io/badge/Helm-%230F1689?style=flat-square&logo=helm&logoColor=white" />
    <br/>
    <img src="https://img.shields.io/badge/license-MIT-green?style=flat-square" />
    <img src="https://img.shields.io/badge/PRs-welcome-brightgreen?style=flat-square" />
  </p>
  <p>
    <a href="#-quick-start">Quick Start</a> •
    <a href="#-architecture">Architecture</a> •
    <a href="#-components">Components</a> •
    <a href="#-config">Config</a>
  </p>
  <br/>
</div>

---

## 🚀 Quick Start

### 🐧 Linux
```bash
# 本地 3 节点集群 + 全量中间件（一行起飞）
bash deploy-k8s-cluster.sh k3d && bash deploy-registry-stack.sh --all

# 按需组合
bash deploy-registry-stack.sh --mysql --redis --kafka --nacos

# 生产环境（3台物理机 K3s HA）
NODE_IPS=10.0.0.1,10.0.0.2,10.0.0.3 bash deploy-k8s-cluster.sh k3s
bash deploy-registry-stack.sh --all
```

### 🪟 Windows
```powershell
# 本地 3 节点集群 + 全量中间件
.\deploy-k8s-cluster.ps1 -WithK3d; .\deploy-registry-stack.ps1 -WithAll

# 按需组合
.\deploy-registry-stack.ps1 -Mysql -Redis -Kafka -Nacos
```

### 🔍 Dry Run
```bash
DRY_RUN=1 bash deploy-registry-stack.sh --all   # Linux
.\deploy-registry-stack.ps1 -DryRun -WithAll     # Windows
```

---

## 🏗 Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    deploy-k8s-cluster.sh/.ps1                     │
│               ⚡ K3s / k3d · 3 节点 HA · Embedded etcd           │
├─────────────────────────────────────────────────────────────────┤
│                    deploy-registry-stack.sh/.ps1                  │
├─────────────────────────────────────────────────────────────────┤
│                                                                   │
│  ┌─ Infrastructure ───────────────────────────────────────────┐  │
│  │  PostgreSQL(3)  MySQL(3)  Redis(3)  MinIO                   │  │
│  ├─ Storage & Coordination ───────────────────────────────────┤  │
│  │  Elasticsearch(3)  MongoDB(3)  ZooKeeper(3)                 │  │
│  ├─ Messaging ────────────────────────────────────────────────┤  │
│  │  Kafka KRaft(3)  RocketMQ(3NS+3B)                          │  │
│  ├─ Discovery & Config ───────────────────────────────────────┤  │
│  │  Nacos(3)  Apollo(3)  ShardingSphere(2)                    │  │
│  ├─ Control & APM ────────────────────────────────────────────┤  │
│  │  Sentinel(2)  SkyWalking(3)                                │  │
│  ├─ Time-Series ──────────────────────────────────────────────┤  │
│  │  TDengine(3)                                                │  │
│  └─ Registry ─────────────────────────────────────────────────┘  │
│     Harbor (镜像库)                                              │
│                                                                   │
│  🛡  All components ≥ 3 nodes · Split-brain safe                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 📦 Components

| # | Component | Linux | Windows | Nodes | Image | Description |
|---|-----------|-------|---------|-------|-------|-------------|
| 1 | 🐬 **MySQL** | `--mysql` | `-Mysql` | 3 | `mysql:8.0` | 一主二从 · 半同步复制 |
| 2 | 🐘 **PostgreSQL** | `--pg` | `-Pg` | 3 | `postgres:16` | 流复制 · hot standby |
| 3 | 🧩 **Redis** | `--redis` | `-Redis` | 3 | `redis:7-alpine` | Sentinel HA |
| 4 | 📦 **MinIO** | `--minio` | `-MinIO` | 1 | `minio/minio` | S3 对象存储 |
| 5 | 📡 **Kafka** | `--kafka` | `-Kafka` | 3 | Bitnami | KRaft · 无 ZK |
| 6 | 🔍 **Elasticsearch** | `--es` | `-Es` | 3 | Elastic | 搜索 + 日志 |
| 7 | 🍃 **MongoDB** | `--mongo` | `-Mongo` | 3 | Bitnami | ReplicaSet |
| 8 | 🦎 **ZooKeeper** | `--zk` | `-Zk` | 3 | Bitnami | 分布式协调 |
| 9 | 🌐 **Nacos** | `--nacos` | `-Nacos` | 3 | Nacos | 注册中心 + 配置中心 |
| 10 | 🚀 **RocketMQ** | `--rocketmq` | `-RocketMQ` | 6 | Apache | 3NS + 3Broker |
| 11 | ⚡ **Sentinel** | `--sentinel` | `-Sentinel` | 2 | Sentinel | 流量治理 Dashboard |
| 12 | 📈 **SkyWalking** | `--skywalking` | `-Skywalking` | 3 | Apache | 分布式 APM 链路追踪 |
| 13 | ⚙️ **Apollo** | `--apollo` | `-Apollo` | 3 | Apollo | 配置中心 |
| 14 | ⏱ **TDengine** | `--tdengine` | `-Tdengine` | 3 | TDengine | 时序数据库 |
| 15 | 🔀 **ShardingSphere** | `--shardingsphere` | `-Shardingsphere` | 2 | Apache | 多主分库 |
| 16 | 🏛 **Harbor** | `--harbor` | `-Harbor` | - | Harbor | 镜像仓库 |
| 17 | 🎯 All In One | `--all` | `-All` | - | - | 一键全量 |

> **注意**: MySQL、PostgreSQL、Redis、MinIO 使用 **官方 Docker 镜像**（无拉取限制）  
> 其余组件使用 Helm + Bitnami/Apache 等社区 Chart

---

## 🔌 Port Mapping

| Port | Service | Description |
|------|---------|-------------|
| `30002` | Harbor HTTP | 镜像库 Web UI |
| `30003` | Harbor HTTPS | 镜像库安全端口 |
| `30006` | SkyWalking UI | 链路追踪控制台 |
| `30007` | Apollo Portal | 配置中心 |
| `30008` | Sentinel Dashboard | 流量治理控制台 |
| `30009` | Sentinel API | 监控 API |
| `30010` | RocketMQ NameServer | 消息队列客户端接入 |
| `30307` | ShardingSphere | 多主分库 MySQL 协议 |

---

## 📁 Config

```
beggar/
├── deploy-k8s-cluster.sh          # 🐧 K8s 集群部署
├── deploy-k8s-cluster.ps1         # 🪟 K8s 集群部署
├── deploy-registry-stack.sh       # 🐧 中间件部署
├── deploy-registry-stack.ps1      # 🪟 中间件部署
└── config/
    ├── manifests/                 # 📜 Raw Kubernetes YAML
    │   ├── mysql-replication.yaml       # MySQL 一主二从
    │   ├── postgresql-ha.yaml           # PostgreSQL 流复制
    │   ├── redis-sentinel.yaml          # Redis Sentinel HA
    │   ├── minio.yaml                   # MinIO 对象存储
    │   ├── rocketmq.yaml                # RocketMQ 3+3
    │   ├── sentinel-dashboard.yaml      # Sentinel 控制台
    │   └── shardingsphere.yaml          # ShardingSphere 分库
    ├── harbor-values.yaml         # Harbor Helm values
    ├── kafka-values.yaml          # Kafka KRaft
    ├── elasticsearch-values.yaml  # Elasticsearch
    ├── nacos-values.yaml          # Nacos
    ├── mongodb-values.yaml        # MongoDB
    ├── zookeeper-values.yaml      # ZooKeeper
    ├── skywalking-values.yaml     # SkyWalking
    ├── apollo-values.yaml         # Apollo
    └── tdengine-values.yaml       # TDengine
```

---

## 🧹 Cleanup

```bash
# Full uninstall
kubectl delete ns registry-stack

# k3d cluster
k3d cluster delete beggar
```

---

<div align="center">
  <sub>Built with ❤️ for Java middlewares</sub>
</div>
