# Beggar - 一键部署 K8s 集群 + 中间件全家桶

## 环境要求

| 工具 | 版本 | 用途 |
|------|------|------|
| `kubectl` | 1.23+ | K8s 操作 |
| `helm` | 3.8+ | 中间件包管理 |
| `Docker` | 20+ | k3d 本地集群需要 |

## 快速开始

### 🐧 Linux

```bash
# 1. 起本地 K3s 集群 (3节点, 需要 Docker)
bash deploy-k8s-cluster.sh k3d

# 2. 一键部署全部中间件
bash deploy-registry-stack.sh --all

# 按需组合
bash deploy-registry-stack.sh --kafka --es --nacos --skywalking

# 先校验不真跑
DRY_RUN=1 bash deploy-registry-stack.sh --all
```

**K3s 原生 HA（3台物理机）：**
```bash
NODE_IPS=10.0.0.1,10.0.0.2,10.0.0.3 bash deploy-k8s-cluster.sh k3s
bash deploy-registry-stack.sh --all
```

### 🪟 Windows

```powershell
# 1. 起集群
.\deploy-k8s-cluster.ps1 -WithK3d

# 2. 全量中间件
.\deploy-registry-stack.ps1 -WithAll

# 按需组合
.\deploy-registry-stack.ps1 -WithKafka -WithElasticsearch -WithNacos -WithSkyWalking

# 先校验
.\deploy-registry-stack.ps1 -DryRun
```

## 中间件一览

| 中间件 | Linux 参数 | Windows 参数 | 节点数 | 说明 |
|--------|-----------|-------------|--------|------|
| PostgreSQL | (基础) | (基础) | 3 | Harbor 元数据 |
| MySQL | (基础) | (基础) | 3 | 应用数据库 |
| Redis | (基础) | (基础) | 3 | 缓存 + Sentinel HA |
| Kafka | `--kafka` | `-WithKafka` | 3 | KRaft 模式 |
| Elasticsearch | `--es` | `-WithElasticsearch` | 3 | 搜索 + 日志 |
| Nacos | `--nacos` | `-WithNacos` | 3 | 注册中心 + 配置中心 |
| RocketMQ | `--rocketmq` | `-WithRocketMQ` | 6 | 3NS + 3Broker |
| Sentinel | `--sentinel` | `-WithSentinel` | 2 | 流量治理 |
| SkyWalking | `--skywalking` | `-WithSkyWalking` | 3 | APM 链路追踪 |
| MongoDB | `--mongo` | `-WithMongoDB` | 3 | NoSQL 文档数据库 |
| ZooKeeper | `--zookeeper` | `-WithZooKeeper` | 3 | 分布式协调 |
| Apollo | `--apollo` | `-WithApollo` | 3 | 配置中心 |
| TDengine | `--tdengine` | `-WithTDengine` | 3 | 时序数据库 |
| MinIO | `--minio` | `-WithMinIO` | 1 | S3 对象存储 |
| Harbor | (始终部署) | (始终部署) | - | 镜像仓库 |

## 端口映射 (NodePort 模式)

| 端口 | 服务 |
|------|------|
| 30002 | Harbor HTTP |
| 30003 | Harbor HTTPS |
| 30006 | SkyWalking UI |
| 30007 | Apollo Portal |
| 30008 | Sentinel Dashboard |
| 30009 | Sentinel API |
| 30010 | RocketMQ NameServer |

## 配置目录

```
config/
├── manifests/
│   ├── rocketmq.yaml              # RocketMQ raw YAML
│   └── sentinel-dashboard.yaml    # Sentinel raw YAML
├── harbor-values.yaml
├── postgresql-values.yaml
├── mysql-values.yaml
├── redis-values.yaml
├── kafka-values.yaml
├── elasticsearch-values.yaml
├── nacos-values.yaml
├── mongodb-values.yaml
├── zookeeper-values.yaml
├── skywalking-values.yaml
├── apollo-values.yaml
└── tdengine-values.yaml
```

## 脚本说明

| 脚本 | 平台 | 功能 |
|------|------|------|
| `deploy-k8s-cluster.sh` | 🐧 Linux | k3d / K3s HA 集群部署 |
| `deploy-registry-stack.sh` | 🐧 Linux | 中间件一键部署 |
| `deploy-k8s-cluster.ps1` | 🪟 Windows | k3d / K3s HA 集群部署 |
| `deploy-registry-stack.ps1` | 🪟 Windows | 中间件一键部署 |

## 卸载

```bash
helm uninstall pg mysql redis kafka elasticsearch mongodb zookeeper nacos skywalking tdengine apollo harbor -n registry-stack 2>/dev/null
kubectl delete pvc -n registry-stack --all
kubectl delete ns registry-stack
```
