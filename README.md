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

The Linux bootstrap supports a freshly installed **Ubuntu Desktop 24.04 LTS / Debian 13 desktop system, x86_64**, with systemd and read/write access to `/dev/kvm`. Copy or extract this repository onto the installed OS, open a desktop terminal as the login user, then run `bash bootstrap-linux.sh` from its directory. The base installs Rancher Desktop from the official repo, starts it with Moby and built-in Kubernetes disabled, and installs k3d. See [Linux installation details](docs/linux-bootstrap.md) for prerequisites, recovery, and verification limits.

```bash
# Preview the full flow
bash bootstrap-linux.sh --dry-run

# Install only the base
bash bootstrap-linux.sh --base-only

# Install the base and create a three-node development cluster
bash bootstrap-linux.sh

# Add a small first workload, or explicitly select the full stack
bash bootstrap-linux.sh --minio
bash bootstrap-linux.sh --all

# Explicitly select the project cluster for standalone middleware commands
KUBECONFIG="$HOME/.kube/beggar-cluster.yaml" bash deploy-registry-stack.sh --minio
```

The standalone commands below assume an existing toolchain and target kubeconfig:

```bash

# Pick what you need
bash deploy-registry-stack.sh --mysql --redis --kafka --nacos

# Start minimum-HA APISIX (2 gateways + 3 etcd; needs at least 3 nodes)
bash deploy-registry-stack.sh --apisix

# Add the platform toolchain (cert-manager/Argo CD/Kyverno/etcd/OpenBao/Loki/Velero/Renovate)
bash deploy-registry-stack.sh --platform-all

# Production: 3 physical machines K3s HA
NODE_IPS=10.0.0.1,10.0.0.2,10.0.0.3 bash deploy-k8s-cluster.sh k3s
export KUBECONFIG="$HOME/.kube/config-beggar"
bash deploy-registry-stack.sh --all

# Validate without deploying
DRY_RUN=1 bash deploy-registry-stack.sh --all
```

### 🪟 Windows

Windows base installation is deferred until the Linux result is reviewed. These commands still require a prepared environment.

```powershell
# Local cluster + full stack
.\deploy-k8s-cluster.ps1 -WithK3d
.\deploy-registry-stack.ps1 -WithAll

# Selective deployment
.\deploy-registry-stack.ps1 -Mysql -Redis -Kafka -Nacos

# Start minimum-HA APISIX (2 gateways + 3 etcd; needs at least 3 nodes)
.\deploy-registry-stack.ps1 -Apisix

# Add the platform toolchain
.\deploy-registry-stack.ps1 -PlatformAll

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
│  Elasticsearch(3)  MongoDB(3)  ZooKeeper(3)  etcd(3)         │
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
│  API Gateways ─────────────────────────────────────────────  │
│  APISIX HA(2 + etcd 3)    ShenYu(2 admin + 2 bootstrap)      │
│                                                               │
│  Time-Series ─────────────────────────────────────────────  │
│  TDengine(3)                                                  │
│                                                               │
│  Registry ────────────────────────────────────────────────  │
│  Harbor (image registry)                                     │
│                                                               │
│  Platform engineering ────────────────────────────────────  │
│  cert-manager  Argo CD  Kyverno  OpenBao(3)  Loki+Alloy      │
│                                                               │
│  🛡  HA profiles use PDBs/anti-affinity; see exceptions below│
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
| 17 | 🛣️ **APISIX HA** | `--apisix` | `-Apisix` | 2+3 | Apache | Minimum-HA API gateway + etcd |
| 18 | 🔗 **ShenYu** | `--shenyu` | `-Shenyu` | 2+2 | Apache | API gateway + admin |
| 19 | 🔌 **Dubbo** | `--dubbo` | `-Dubbo` | 2 | Apache | RPC admin console (+ZK) |
| 20 | 📋 **Seata** | `--seata` | `-Seata` | 2 | Apache | Distributed transactions |
| 21 | ⏰ **XXL-JOB** | `--xxl-job` | `-XxlJob` | 2 | xuxueli | Distributed scheduler (+MySQL) |
| 22 | 📊 **Prometheus+Grafana** | `--prometheus` | `-Prometheus` | 1+1 | Prometheus/Grafana | Monitoring stack |
| 23 | 💬 **Pulsar** | `--pulsar` | `-Pulsar` | 3+1 | Apache | Cloud-native messaging |
| 24 | 🌊 **Flink** | `--flink` | `-Flink` | 1+2 | Apache | Stream processing |
| 25 | 🏗️ **Jenkins** | `--jenkins` | `-Jenkins` | 1 | Jenkins | CI/CD |
| 26 | 🟢 **Spring Boot Admin** | `--spring-boot-admin` | `-Sba` | 2 | codecentric | App monitoring |
| 27 | 🪪 **cert-manager** | `--cert-manager` | `-CertManager` | 2+3+2 | Jetstack | Certificate lifecycle controllers and CRDs; no Issuer created |
| 28 | 🚢 **Argo CD** | `--argocd` | `-ArgoCD` | 2+2+2+HA Redis | Argo Project | GitOps continuous delivery control plane |
| 29 | 🛡️ **Kyverno** | `--kyverno` | `-Kyverno` | 3+2+2+2 | Kyverno | Policy admission and reports control plane; no policies installed |
| 30 | 🧱 **Independent etcd** | `--etcd` | `-Etcd` | 3 | Bitnami/etcd | Standalone coordination store; not shared with APISIX |
| 31 | 🔐 **OpenBao** | `--openbao` | `-OpenBao` | 3 | OpenBao | Raft secret store; manual init/unseal |
| 32 | 🪵 **Loki + Alloy** | `--loki` | `-Loki` | 3+3+3+2+2 | Grafana | HA log store and clustered collection (+MinIO/S3) |
| 33 | 💾 **Velero** | `--velero` | `-Velero` | 1+DaemonSet | Velero | Kubernetes backup controller and node agents (+MinIO/S3) |
| 34 | 🤖 **Renovate** | `--renovate` | `-Renovate` | CronJob | Renovate | Dependency updates; suspended by default |
| 35 | 🧰 **Platform tools** | `--platform-all` | `-PlatformAll` | - | - | Deploy rows 27–34; leaves `--all` unchanged |
| 36 | 🎯 **All** | `--all` | `-WithAll` | - | - | Deploy the original middleware set |

> 💡 `--loki` and `--velero` automatically include MinIO. `--platform-all` contains only the platform tools and does not expand the existing `--all` set.

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
| `30011` | APISIX HTTP | API gateway entrypoint |
| `30012` | Argo CD HTTP service port | Routes to the Argo CD server |
| `30013` | Argo CD HTTPS | GitOps UI/API over TLS |
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
    ├── etcd-values.yaml              # Independent 3-node etcd
    ├── minio-values.yaml             # MinIO and shared buckets
    ├── skywalking-values.yaml        # SkyWalking config (needs ES)
    ├── apollo-values.yaml            # Apollo config (needs MySQL)
    ├── tdengine-values.yaml          # TDengine config
    ├── apisix-values.yaml            # APISIX gateway config
    ├── cert-manager-values.yaml      # cert-manager HA control plane
    ├── argocd-values.yaml            # Argo CD GitOps control plane
    ├── kyverno-values.yaml           # Kyverno policy control plane
    ├── openbao-values.yaml           # OpenBao 3-node Raft
    ├── loki-values.yaml              # Loki SimpleScalable HA
    ├── alloy-values.yaml             # Clustered Alloy collectors
    ├── velero-values.yaml            # Velero + MinIO/S3
    ├── renovate-values.yaml          # Suspended Renovate CronJob
    ├── shenyu-values.yaml            # ShenYu gateway config
    ├── prometheus-values.yaml        # Prometheus+Grafana config
    ├── pulsar-values.yaml            # Pulsar messaging config
    └── jenkins-values.yaml           # Jenkins CI/CD config
```

## 🛣️ APISIX notes

Like the other Helm middleware, APISIX HA is deployed through the `helm` / `kubectl` tools supplied by Rancher Desktop. One `-Apisix` command starts two APISIX and three etcd Pods. Its HTTP entrypoint is `http://<NodeIP>:30011`; the Admin API stays cluster-internal through a ClusterIP service. Hard pod anti-affinity spreads each APISIX and etcd replica across separate nodes, so the deployment will not complete on a cluster with fewer than three schedulable nodes. This profile does not enable an Ingress Controller; configure routes with the Admin API. `--all` installs both APISIX HA and ShenYu, but only one gateway should own a given external domain or entrypoint.

## 🧰 Platform tool notes

Install all platform additions in one command. Loki and Velero automatically include MinIO in the same namespace:

```bash
bash deploy-registry-stack.sh --platform-all
# Windows: .\deploy-registry-stack.ps1 -PlatformAll
```

Independent etcd uses three replicas, hard anti-affinity, and a PDB with `minAvailable: 2`. Its endpoint is `etcd.registry-stack.svc:2379`, and it never replaces APISIX's bundled etcd. The repository password is only a local/demo default; change `config/etcd-values.yaml` before using a shared environment.

cert-manager installs only the controllers and CRDs. Create an `Issuer` or `ClusterIssuer` and `Certificate` resources separately for your environment.

Argo CD exposes a NodePort service at `https://<NodeIP>:30013`. The initial admin password remains in the chart-created secret; rotate it before use outside a trusted network.

Kyverno installs only the admission, background, cleanup, and reports controllers. No policy bundle is installed by default, so enforcement begins only after you add policies.

OpenBao intentionally remains uninitialized and sealed after installation. Securely retain the recovery keys and root token from the first command, then initialize one node, join the two followers to Raft, and unseal each node:

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

Loki runs SimpleScalable with three write, read, and backend replicas plus two gateway and two Alloy replicas. Alloy clustering shards Pod-log targets to prevent duplicate collection. The default MinIO profile remains a single-replica development dependency, so this provides Loki compute-plane HA, not end-to-end storage HA. Point `config/loki-values.yaml` and `config/velero-values.yaml` at an external HA S3 service for production.

Velero installation does not create or run any backup or restore. After validating external object storage, use the Velero CLI to opt into a schedule:

```bash
velero schedule create registry-stack-daily --schedule "0 3 * * *" --include-namespaces registry-stack
velero backup get
# Restore is destructive; verify the backup and target cluster first.
velero restore create --from-backup '<BACKUP_NAME>'
```

The official Velero server currently uses one controller and has no leader election. This project does not scale it unsafely to pretend it is HA. Kubernetes can recreate the Deployment after a node failure and node-agent covers every node, but controller operations pause briefly during failover.

Renovate is installed as a suspended CronJob and cannot access repositories without credentials. Create a GitHub Secret and explicitly enable it:

```bash
kubectl create secret generic renovate-credentials -n registry-stack \
  --from-literal=RENOVATE_PLATFORM=github \
  --from-literal=RENOVATE_TOKEN='<TOKEN>'
kubectl patch cronjob renovate -n registry-stack --type merge -p '{"spec":{"suspend":false}}'
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
