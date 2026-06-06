# Beggar - 一键部署 K8s 集群 + 中间件全家桶

从裸机到完整的中间件集群，**一条命令全搞定**。

## 环境要求

| 工具 | 版本 | 用途 |
|------|------|------|
| PowerShell Core `pwsh` | 7.0+ | 脚本运行环境（Linux 需安装，Windows 自带） |
| `kubectl` | 1.23+ | K8s 操作 |
| `helm` | 3.8+ | 中间件包管理 |
| `Docker` | 20+ | k3d 本地集群模式需要 |

**Linux 安装 pwsh：**
```bash
# Ubuntu/Debian
curl -fsSL https://aka.ms/install-powershell | bash

# 验证
pwsh --version
```

**所有脚本用 pwsh 执行：**
```bash
pwsh ./deploy-k8s-cluster.ps1 -WithK3d
pwsh ./deploy-registry-stack.ps1 -WithAll
```

## 架构全景

```
┌─────────────────────────────────────────────────────────┐
│                    deploy-k8s-cluster.ps1                 │
│              一键部署 K3s HA 集群 (3节点)                  │
├─────────────────────────────────────────────────────────┤
│                    deploy-registry-stack.ps1              │
├─────────────────────────────────────────────────────────┤
│                                                          │
│  ┌─────────────────────────────────────────────────┐    │
│  │  Layer 1: 基础设施                                │    │
│  │  ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌──────┐  │    │
│  │  │PostgreSQL│ │  MySQL  │ │  Redis  │ │MinIO │  │    │
│  │  │  3-node │ │ 3-node  │ │ 3-node  │ │(opt) │  │    │
│  │  └─────────┘ └─────────┘ └─────────┘ └──────┘  │    │
│  ├─────────────────────────────────────────────────┤    │
│  │  Layer 2: 存储 & 协调                             │    │
│  │  ┌──────────────┐ ┌────────┐ ┌────────────┐    │    │
│  │  │ Elasticsearch│ │MongoDB │ │ ZooKeeper  │    │    │
│  │  │   3-node     │ │3-node  │ │  3-node    │    │    │
│  │  └──────────────┘ └────────┘ └────────────┘    │    │
│  ├─────────────────────────────────────────────────┤    │
│  │  Layer 3: 消息                                   │    │
│  │  ┌───────────┐ ┌──────────────────────┐        │    │
│  │  │   Kafka   │ │     RocketMQ         │        │    │
│  │  │3-node KRaft│ │ 3NS + 3Broker       │        │    │
│  │  └───────────┘ └──────────────────────┘        │    │
│  ├─────────────────────────────────────────────────┤    │
│  │  Layer 4: 注册/配置/治理                          │    │
│  │  ┌─────────┐ ┌─────────┐ ┌────────────┐       │    │
│  │  │  Nacos  │ │  Apollo │ │Sentinel Dash│       │    │
│  │  │ 3-node  │ │ 3-node  │ │  2-node    │       │    │
│  │  └─────────┘ └─────────┘ └────────────┘       │    │
│  ├─────────────────────────────────────────────────┤    │
│  │  Layer 5: 可观测性                               │    │
│  │  ┌────────────┐ ┌───────────┐                  │    │
│  │  │  SkyWalking│ │  Harbor   │                  │    │
│  │  │ OAP 3-node │ │ 镜像库    │                  │    │
│  │  └────────────┘ └───────────┘                  │    │
│  ├─────────────────────────────────────────────────┤    │
│  │  Layer 6: 时序                                  │    │
│  │  ┌───────────┐                                  │    │
│  │  │  TDengine │                                  │    │
│  │  │  3-node   │                                  │    │
│  │  └───────────┘                                  │    │
│  └─────────────────────────────────────────────────┘    │
│                                                          │
│  所有中间件 ≥3节点，防脑裂                                  │
└─────────────────────────────────────────────────────────┘
```

## 使用方式

### Step 1: 部署 K8s 集群（可选）

**方式 A: k3d（本地 Docker，适合开发）**
```powershell
.\deploy-k8s-cluster.ps1 -WithK3d -K3dNodeCount 3
```

**方式 B: K3s HA（3台物理机/VM，适合生产）**
```powershell
.\deploy-k8s-cluster.ps1 -NodeIps "192.168.1.10","192.168.1.11","192.168.1.12" -SshKeyPath "C:\Users\me\.ssh\id_rsa"
```

**方式 C: 已有集群**
```powershell
.\deploy-k8s-cluster.ps1 -SkipRegistryStack
# 确保 kubectl 已配置好集群访问
```

### Step 2: 部署中间件

```powershell
# 基础三件套（始终部署）：PostgreSQL + MySQL + Redis + Harbor
.\deploy-registry-stack.ps1

# 全家桶（全部中间件）
.\deploy-registry-stack.ps1 -WithAll

# 按需组合
.\deploy-registry-stack.ps1 -WithKafka -WithElasticsearch -WithNacos -WithSkyWalking
```

## 参数说明

### deploy-registry-stack.ps1

| 参数 | 说明 | 默认 |
|------|------|------|
| `-WithAll` | 部署全部中间件 | false |
| `-WithMinIO` | MinIO 对象存储 | false |
| `-WithKafka` | Kafka 3节点 (KRaft) | false |
| `-WithElasticsearch` | Elasticsearch 3节点 | false |
| `-WithNacos` | Nacos 3节点 (需要 MySQL) | false |
| `-WithRocketMQ` | RocketMQ 3+3节点 | false |
| `-WithSentinel` | Sentinel Dashboard 2节点 | false |
| `-WithSkyWalking` | SkyWalking OAP 3节点 (需要 ES) | false |
| `-WithMongoDB` | MongoDB 3节点 ReplicaSet | false |
| `-WithZooKeeper` | ZooKeeper 3节点 | false |
| `-WithApollo` | Apollo 3节点 (需要 MySQL) | false |
| `-WithTDengine` | TDengine 3节点 | false |
| `-WithIngress` | 使用 Ingress (默认 NodePort) | false |
| `-Namespace` | K8s 命名空间 | registry-stack |

### deploy-k8s-cluster.ps1

| 参数 | 说明 | 默认 |
|------|------|------|
| `-WithK3d` | 使用 k3d 本地部署 | false |
| `-K3dNodeCount` | k3d 节点数量 | 3 |
| `-NodeIps` | 物理机 IP 数组 | 空 |
| `-SshUser` | SSH 用户 | root |
| `-K3sVersion` | K3s 版本 | v1.30.2+k3s2 |
| `-SkipRegistryStack` | 跳过中间件部署 | false |

## 服务端口映射（NodePort 模式）

| 端口 | 服务 | 说明 |
|------|------|------|
| 30002 | Harbor HTTP | 镜像库 Web UI |
| 30003 | Harbor HTTPS | 镜像库安全端口 |
| 30006 | SkyWalking UI | 链路追踪控制台 |
| 30007 | Apollo Portal | 配置中心控制台 |
| 30008 | Sentinel Dashboard | 流量控制控制台 |
| 30009 | Sentinel API | 监控 API |
| 30010 | RocketMQ NameServer | 消息队列接入 |

## 配置目录

| 文件 | 说明 |
|------|------|
| `config/harbor-values.yaml` | Harbor (外部 PG + Redis + PVC) |
| `config/postgresql-values.yaml` | PostgreSQL 3-node HA (pgpool) |
| `config/mysql-values.yaml` | MySQL 3-node 半同步复制 |
| `config/redis-values.yaml` | Redis 3-node Sentinel |
| `config/kafka-values.yaml` | Kafka 3-node KRaft |
| `config/elasticsearch-values.yaml` | Elasticsearch 3-node |
| `config/nacos-values.yaml` | Nacos 3-node + MySQL |
| `config/mongodb-values.yaml` | MongoDB 3-node ReplicaSet |
| `config/zookeeper-values.yaml` | ZooKeeper 3-node |
| `config/skywalking-values.yaml` | SkyWalking OAP 3-node + ES |
| `config/apollo-values.yaml` | Apollo 3-node + MySQL |
| `config/tdengine-values.yaml` | TDengine 3-node |
| `config/manifests/rocketmq.yaml` | RocketMQ (NameServer 3 + Broker 3) |
| `config/manifests/sentinel-dashboard.yaml` | Sentinel Dashboard 2-node |

## 卸载

```powershell
# 卸载中间件
helm uninstall pg mysql redis harbor kafka elasticsearch nacos mongodb zookeeper skywalking tdengine apollo -n registry-stack

# 清理 PVC
kubectl delete pvc -n registry-stack --all

# 删除命名空间
kubectl delete ns registry-stack

# 删除 k3d 集群
k3d cluster delete beggar-cluster
```
