<div align="center">
  <img src="icon.svg" width="64" height="64" alt="Beggar logo" />
  <h1>Beggar</h1>
  <p><strong>From bare metal to full middleware stack — one command to rule them all</strong></p>
  <p>
    <img src="https://img.shields.io/badge/Linux-%23FCC624?style=flat-square&logo=linux&logoColor=black" />
    <img src="https://img.shields.io/badge/Windows-%230078D4?style=flat-square&logo=windows&logoColor=white" />
    <img src="https://img.shields.io/badge/K3s-%23FFC61C?style=flat-square&logo=k3s&logoColor=black" />
    <img src="https://img.shields.io/badge/Helm-%230F1689?style=flat-square&logo=helm&logoColor=white" />
    <img src="https://img.shields.io/badge/license-MIT-green?style=flat-square" />
  </p>
  <p>
    <a href="#-quick-start">Quick Start</a> •
    <a href="#-architecture">Architecture</a> •
    <a href="#-components">Components</a> •
    <a href="#-configuration">Configuration</a>
  </p>
  <p>
    <a href="README.zh.md">🇨🇳 中文版</a>
  </p>
  <br/>
</div>

---

## 🚀 Quick Start

### 🐧 Linux

```bash
# One-shot: 3-node local cluster + all middleware
bash deploy-k8s-cluster.sh k3d && bash deploy-registry-stack.sh --all

# Pick what you need
bash deploy-registry-stack.sh --mysql --redis --kafka --nacos

# Production: 3 physical machines K3s HA
NODE_IPS=10.0.0.1,10.0.0.2,10.0.0.3 bash deploy-k8s-cluster.sh k3s
bash deploy-registry-stack.sh --all

# Validate without deploying
DRY_RUN=1 bash deploy-registry-stack.sh --all
```

### 🪟 Windows

```powershell
# Local cluster + full stack
.\deploy-k8s-cluster.ps1 -WithK3d
.\deploy-registry-stack.ps1 -WithAll

# Selective deployment
.\deploy-registry-stack.ps1 -Mysql -Redis -Kafka -Nacos

# Dry run
.\deploy-registry-stack.ps1 -DryRun -WithAll
```

---

## 🏗 Architecture

```
┌──────────────────────────────────────────────────────────────┐
│                    deploy-k8s-cluster.sh/.ps1                  │
│              K3s / k3d · 3-node HA · Embedded etcd            │
├──────────────────────────────────────────────────────────────┤
│                    deploy-registry-stack.sh/.ps1               │
├──────────────────────────────────────────────────────────────┤
│                                                               │
│  Infrastructure ───────────────────────────────────────────  │
│  PostgreSQL(3)    MySQL(3)    Redis(3)    MinIO              │
│                                                               │
│  Storage & Coordination ──────────────────────────────────  │
│  Elasticsearch(3)  MongoDB(3)  ZooKeeper(3)                  │
│                                                               │
│  Messaging ───────────────────────────────────────────────  │
│  Kafka KRaft(3)    RocketMQ(3NS + 3Broker)                   │
│                                                               │
│  Discovery & Config ──────────────────────────────────────  │
│  Nacos(3)    Apollo(3)    ShardingSphere(2)                  │
│                                                               │
│  Control & APM ───────────────────────────────────────────  │
│  Sentinel Dashboard(2)    SkyWalking OAP(3)                  │
│                                                               │
│  Time-Series ─────────────────────────────────────────────  │
│  TDengine(3)                                                  │
│                                                               │
│  Registry ────────────────────────────────────────────────  │
│  Harbor (image registry)                                     │
│                                                               │
│  🛡  All components ≥ 3 nodes · Split-brain safe             │
└──────────────────────────────────────────────────────────────┘
```

---

## 📦 Components

| # | Component | Linux | Windows | Nodes | Image | Description |
|---|-----------|-------|---------|-------|-------|-------------|
| 1 | 🐬 **MySQL** | `--mysql` | `-Mysql` | 3 | Official `mysql:8.0` | 1 primary + 2 replicas |
| 2 | 🐘 **PostgreSQL** | `--pg` | `-Pg` | 3 | Official `postgres:16` | Streaming replication |
| 3 | 🧩 **Redis** | `--redis` | `-Redis` | 3 | Official `redis:7` | Sentinel HA |
| 4 | 📦 **MinIO** | `--minio` | `-MinIO` | 1 | Official `minio/minio` | S3-compatible storage |
| 5 | 📡 **Kafka** | `--kafka` | `-Kafka` | 3 | Bitnami | KRaft mode, no ZK |
| 6 | 🔍 **Elasticsearch** | `--es` | `-Es` | 3 | Elastic | Search & analytics |
| 7 | 🍃 **MongoDB** | `--mongo` | `-Mongo` | 3 | Bitnami | ReplicaSet |
| 8 | 🦎 **ZooKeeper** | `--zk` | `-Zk` | 3 | Bitnami | Coordination service |
| 9 | 🌐 **Nacos** | `--nacos` | `-Nacos` | 3 | Nacos official | Service discovery & config |
| 10 | 🚀 **RocketMQ** | `--rocketmq` | `-RocketMQ` | 6 | Apache | 3NS + 3Broker |
| 11 | ⚡ **Sentinel** | `--sentinel` | `-Sentinel` | 2 | Sentinel | Flow control dashboard |
| 12 | 📈 **SkyWalking** | `--skywalking` | `-Skywalking` | 3 | Apache | Distributed APM |
| 13 | ⚙️ **Apollo** | `--apollo` | `-Apollo` | 3 | Apollo official | Config center |
| 14 | ⏱ **TDengine** | `--tdengine` | `-Tdengine` | 3 | TDengine | Time-series database |
| 15 | 🔀 **ShardingSphere** | `--shardingsphere` | `-Shardingsphere` | 2 | Apache | MySQL sharding |
| 16 | 🏛 **Harbor** | `--harbor` | `-Harbor` | - | Harbor CNCF | Image registry |
| 18 | 🔗 **ShenYu** | `--shenyu` | `-Shenyu` | 2+2 | Apache | API gateway + admin |
| 19 | 🔌 **Dubbo** | `--dubbo` | `-Dubbo` | 2 | Apache | RPC admin console (+ZK) |
| 20 | 📋 **Seata** | `--seata` | `-Seata` | 2 | Apache | Distributed transactions |
| 21 | ⏰ **XXL-JOB** | `--xxl-job` | `-XxlJob` | 2 | xuxueli | Distributed scheduler (+MySQL) |
| 22 | 📊 **Prometheus+Grafana** | `--prometheus` | `-Prometheus` | 1+1 | Prometheus/Grafana | Monitoring stack |
| 23 | 💬 **Pulsar** | `--pulsar` | `-Pulsar` | 3+1 | Apache | Cloud-native messaging |
| 24 | 🌊 **Flink** | `--flink` | `-Flink` | 1+2 | Apache | Stream processing |
| 25 | 🏗️ **Jenkins** | `--jenkins` | `-Jenkins` | 1 | Jenkins | CI/CD |
| 26 | 🟢 **Spring Boot Admin** | `--spring-boot-admin` | `-Sba` | 2 | codecentric | App monitoring |
| 27 | 🎯 **All** | `--all` | `-WithAll` | - | - | Deploy everything |

> 💡 MySQL, PostgreSQL, Redis, MinIO use **official Docker images** — no Bitnami pull limits.

---

## 🔌 Port Mapping (NodePort)

| NodePort | Service | Description |
|----------|---------|-------------|
| `30002` | Harbor HTTP | Image registry UI |
| `30003` | Harbor HTTPS | Image registry secure |
| `30006` | SkyWalking UI | APM dashboard |
| `30007` | Apollo Portal | Config center UI |
| `30008` | Sentinel Dashboard | Flow control console |
| `30009` | Sentinel API | Monitoring API |
| `30010` | RocketMQ NameServer | Message queue client |
| `30307` | ShardingSphere-Proxy | MySQL sharding endpoint |

---

## 📁 Configuration

```
beggar/
├── deploy-k8s-cluster.sh             # 🐧 Linux: K3s cluster setup
├── deploy-k8s-cluster.ps1            # 🪟 Windows: K3s cluster setup
├── deploy-registry-stack.sh          # 🐧 Linux: Middleware deploy
├── deploy-registry-stack.ps1         # 🪟 Windows: Middleware deploy
└── config/
    ├── manifests/                    # 📜 Raw Kubernetes YAML
    │   ├── mysql-replication.yaml          # MySQL primary-replica
    │   ├── postgresql-ha.yaml              # PostgreSQL streaming
    │   ├── redis-sentinel.yaml             # Redis Sentinel HA
    │   ├── minio.yaml                      # MinIO object storage
    │   ├── rocketmq.yaml                   # RocketMQ 3+3
    │   ├── sentinel-dashboard.yaml         # Sentinel dashboard
    │   ├── shardingsphere.yaml             # ShardingSphere proxy
    │   ├── dubbo-admin.yaml               # Dubbo-Admin (+ZK)
    │   ├── seata.yaml                     # Seata distributed TX
    │   ├── xxl-job.yaml                   # XXL-JOB scheduler
    │   ├── xxl-job-init.sql               # XXL-JOB SQL init
    │   ├── flink.yaml                     # Flink session cluster
    │   └── spring-boot-admin.yaml         # SBA app monitoring
    ├── harbor-values.yaml            # Harbor Helm config
    ├── kafka-values.yaml             # Kafka KRaft config
    ├── elasticsearch-values.yaml     # Elasticsearch config
    ├── nacos-values.yaml             # Nacos config (needs MySQL)
    ├── mongodb-values.yaml           # MongoDB config
    ├── zookeeper-values.yaml         # ZooKeeper config
    ├── skywalking-values.yaml        # SkyWalking config (needs ES)
    ├── apollo-values.yaml            # Apollo config (needs MySQL)
    ├── tdengine-values.yaml          # TDengine config
    ├── shenyu-values.yaml            # ShenYu gateway config
    ├── prometheus-values.yaml        # Prometheus+Grafana config
    ├── pulsar-values.yaml            # Pulsar messaging config
    └── jenkins-values.yaml           # Jenkins CI/CD config
```

---

## 🧹 Cleanup

```bash
# Remove all middleware
kubectl delete ns registry-stack

# Delete local k3d cluster
k3d cluster delete beggar
```

---

<div align="blank">
  <sub>Built for the Java middleware ecosystem · ⭐ Star & PR welcome!</sub>
  <br/>
  <a href="README.zh.md">🇨🇳 中文版</a>
</div>
