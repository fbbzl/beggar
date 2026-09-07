# Linux 基座安装

首版支持全新安装的 Ubuntu Desktop 24.04 LTS（noble）与带图形桌面的 Debian 13（trixie），仅限 x86_64。系统需要 systemd，以及 `/dev/kvm` 的读写权限。操作系统和桌面会话本身是安装入口的前置条件；将整个项目复制或解压到目标机器后，在登录用户的桌面终端里进入仓库目录执行命令。

此处的“基座”是 Rancher Desktop、k3d，以及 Rancher Desktop 提供的 `docker` / `kubectl` / `helm` / `nerdctl`。首次配置时脚本启动 Rancher Desktop，选择 `moby` 并关闭内置 Kubernetes；已有配置只启动和检查，不自动切换引擎或关闭已有 Kubernetes。Windows 基座等 Linux 效果确认后再做。

## 从空白系统开始

```bash
# 只打印计划；不安装、联网或创建集群
bash bootstrap-linux.sh --dry-run

# 一键安装基座并启动 Rancher Desktop，不创建集群
bash bootstrap-linux.sh --base-only

# 仅预览基座安装
bash bootstrap-linux.sh --base-only --dry-run

# 安装基座，启动 Rancher Desktop，并创建 1 个 server + 2 个 agent
bash bootstrap-linux.sh

# 查看实际效果：应显示三个 Ready 节点
kubectl --kubeconfig "$HOME/.kube/beggar-cluster.yaml" get nodes -o wide

# 先安装小范围工作负载，再按需增加组件
bash bootstrap-linux.sh --minio
kubectl --kubeconfig "$HOME/.kube/beggar-cluster.yaml" -n registry-stack get pods
```

这是单机三节点开发集群；三个容器共享一台主机，不代表控制面或物理主机高可用。Rancher Desktop 官方建议至少 4 核、8 GiB 内存；如果还要跑中间件，资源预算要继续上调。首轮建议先装基座与 MinIO。

API 固定绑定本机 `127.0.0.1:6445`；项目 NodePort 的 30000–30020 映射也只绑定本机回环地址。远程查看服务时使用 SSH 端口转发或显式执行 `kubectl port-forward`，不要把 kubeconfig 里的管理凭据暴露出去。端口已占用时安装会停止，不会自动结束现有服务。

## 分阶段执行

```bash
# 仅安装/检查基座，不建集群
bash install-linux-base.sh
bash install-linux-base.sh --check

# 已有基座后，仅创建/检查项目集群
bash deploy-k8s-cluster.sh k3d

# 明确项目 kubeconfig，再部署所选组件
KUBECONFIG="$HOME/.kube/beggar-cluster.yaml" bash deploy-registry-stack.sh --minio

# 全量组件仅在明确需要并准备相应资源后选择
bash bootstrap-linux.sh --all
```

`bootstrap-linux.sh --check` 只检查基座，不代表集群和中间件验收完成。完整入口默认使用当前登录用户的家目录写 kubeconfig，如果 `/dev/kvm` 存在但当前用户没有权限，安装入口会通过 sudo 将当前用户加入 `kvm` 组，返回状态码 2 并提示注销后重跑。不会自动注销或重启；`--check` 与 `--dry-run` 不修改组权限。

可通过 `K3D_CLUSTER`、`K3D_NODES`、`BEGGAR_KUBECONFIG` 调整集群名称、节点数量与配置路径；`BEGGAR_KUBECONFIG` 必须是单个绝对路径。默认三节点用于满足已有多副本组件的调度需求。`K3D_IMAGE` 默认 `rancher/k3s:v1.35.5-k3s1`。

Rancher Desktop 从官方 stable APT 源安装，`k3d` 仍然单独安装并校验官方 SHA256；已有安装保留，不自动升级或卸载。首次配置 Rancher Desktop 时，`rdctl start --application.start-in-background --application.admin-access=true --application.path-management-strategy rcfiles --container-engine.name=moby --kubernetes.enabled=false` 会设置本仓库需要的运行状态，并创建 `/var/run/docker.sock` 供当前工具链使用。

启动后最多等待 10 分钟，并通过 `rdctl list-settings` 与 Docker 检查就绪；`jq` 会随基础依赖安装。已有配置不兼容时停止，由用户在 Rancher Desktop 中调整后重跑。

K3s 远程模式默认使用 SSH `accept-new` 和 `$HOME/.ssh/known_hosts`；如需严格校验，可设置 `SSH_STRICT_HOST_KEY_CHECKING=yes` 与 `SSH_KNOWN_HOSTS`，脚本不会关闭主机密钥校验。

## 失败与重跑

- 不支持的系统、架构、没有 systemd、没有图形桌面会话，会在安装前停止；缺少 KVM 设备时需要先启用硬件虚拟化并加载驱动。
- 下载失败或校验不通过时停止，不把下载内容作为安装脚本执行。
- 已有 `rancher-desktop` 包与可用的 `k3d` 会复用；中断后留下的 APT 源文件与官方下载内容完全一致时也会复用，内容冲突则保留现场并停止。
- 同名集群会复用并验证节点数量、Ready 状态；不自动删除、重建或改变拓扑。失败的创建保留现场，不自动回滚删除。
- 已有项目 kubeconfig 会保留；如果指向其他集群或已过期，指定新的 `BEGGAR_KUBECONFIG` 路径后重跑。
- 任一步骤失败都不应当作整个安装完成。修复后重跑同一命令，已完成阶段会被检查和复用。

本轮不提供自动卸载或数据回滚；恢复以保留安装包、容器、卷和配置为原则。中间件来自既有 Helm / YAML 配置，它们的外部镜像可用性和各自初始化要求仍需按组件验证。

## 验证边界

开发和 QA 使用隔离的命令模拟验证平台识别、预览无副作用、错误传播、重跑和集群目标保护。真实验收仍需在 Ubuntu 24.04 与 Debian 13 的桌面主机上执行安装，记录 Rancher Desktop 已启动、本地 Docker 可用、三个 Ready 节点，以及所选工作负载的就绪状态。当前 Windows 工作区没有可用 Docker daemon，不能将模拟测试标为 Linux 实机安装通过。

## 选型依据

- [Rancher Desktop 安装与运行要求](https://docs.rancherdesktop.io/getting-started/installation/)
- [Rancher Desktop `rdctl` 命令参考](https://docs.rancherdesktop.io/references/rdctl-command-reference/)
- [k3d kubeconfig 管理](https://k3d.io/v5.8.3/usage/kubeconfig/)
