# ImmortalWrt for Orange Pi R2S

基于 [ImmortalWrt](https://github.com/immortalwrt/immortalwrt) 的 Orange Pi R2S (RISC-V KY X1) 定制固件。

## 硬件信息

- **SoC**: 进迭时空 KY X1 (RISC-V)
- **内核**: Linux 6.6.119
- **网卡**: 2x RTL8125 (2.5GbE) + 2x 千兆口

## 网口配置

| 接口 | 位置 | 速率 | 默认角色 |
|------|------|------|----------|
| eth3 | 靠近电源接口 | 2.5GbE | **WAN** |
| eth2 | 靠近 eth3 | 2.5GbE | LAN |
| eth1 | 千兆口 | 1GbE | LAN |
| eth0 | 千兆口 | 1GbE | LAN |

## 默认配置

- **IP 地址**: `10.0.2.1`
- **用户名**: `root`
- **密码**: 无

## 优化说明

### 1. 网卡性能优化

- 使用 `kmod-r8125` 驱动（版本 9.016.01-NAPI-RSS）
- 启用 RSS (Receive Side Scaling) 多队列支持
- 配置：4 RX 队列 + 2 TX 队列

```
# ethtool -l eth2
Channel parameters for eth2:
Pre-set maximums:
RX:        4
TX:        2
Current hardware settings:
RX:        4
TX:        2
```

### 2. CPU 负载优化

为避免不必要的内核线程占用 CPU，本固件禁用了以下功能：

| 配置项 | 说明 | 禁用原因 |
|--------|------|----------|
| `CONFIG_POWERVR_ROGUE` | PowerVR GPU 驱动 | 路由器不需要 GPU 渲染 |
| `CONFIG_X1_REMOTEPROC` | KY X1 远程处理器驱动 | 产生 vq0/vq1 内核线程 |
| `CONFIG_REMOTEPROC` | 远程处理器子系统 | 用于协处理器通信，路由器不需要 |
| `CONFIG_RPMSG` | 远程消息子系统 | REMOTEPROC 的依赖 |

**症状**：未禁用时，`vq0` 和 `vq1` 内核线程会处于 D (不可中断) 状态，导致系统负载持续为 2.0。

<details>
<summary>如何重新启用这些功能</summary>

如果需要使用 GPU 或协处理器功能（如多媒体应用、AI 推理等），可以重新启用：

1. 编辑内核配置文件：
```bash
nano target/linux/ky/riscv64/config-6.6
```

2. 修改以下配置项：
```
# GPU (PowerVR) 支持
CONFIG_POWERVR_ROGUE=y

# 远程处理器支持（启用 vq0/vq1）
CONFIG_REMOTEPROC=y
CONFIG_REMOTEPROC_CDEV=y
CONFIG_RPMSG=y
CONFIG_RPMSG_CHAR=y
CONFIG_RPMSG_VIRTIO=y
CONFIG_X1_REMOTEPROC=y
```

3. 重新编译内核：
```bash
./build.sh kernel-rebuild
```

**注意**：启用后系统负载会增加约 2.0，这是正常现象。

</details>

### 3. 性能测试

iperf3 测试结果（2.5G 网口）：

| 方向 | 速率 |
|------|------|
| 上传 (客户端→路由器) | **1.99 Gbps** |
| 下载 (路由器→客户端) | **1.94 Gbps** |

<details>
<summary>详细测试数据</summary>

**上传测试 (客户端→路由器)**
```
~ iperf3-darwin -c 10.0.2.1 -p 5201 -t 10
Connecting to host 10.0.2.1, port 5201
[  5] local 10.0.2.117 port 53420 connected to 10.0.2.1 port 5201
[ ID] Interval           Transfer     Bitrate         Retr  Cwnd          RTT
[  5]   0.00-1.00   sec   237 MBytes  1.99 Gbits/sec  183   2.47 MBytes   10ms
[  5]   1.00-2.00   sec   237 MBytes  1.99 Gbits/sec    0   2.58 MBytes   11ms
[  5]   2.00-3.00   sec   237 MBytes  1.99 Gbits/sec    0   2.67 MBytes   11ms
[  5]   3.00-4.00   sec   238 MBytes  2.00 Gbits/sec    0   2.73 MBytes   11ms
[  5]   4.00-5.00   sec   239 MBytes  2.00 Gbits/sec    0   2.78 MBytes   12ms
[  5]   5.00-6.00   sec   238 MBytes  2.00 Gbits/sec    0   2.81 MBytes   9ms
[  5]   6.00-7.00   sec   237 MBytes  1.99 Gbits/sec    0   2.83 MBytes   12ms
[  5]   7.00-8.00   sec   238 MBytes  2.00 Gbits/sec    0   2.86 MBytes   13ms
[  5]   8.00-9.00   sec   238 MBytes  2.00 Gbits/sec    0   2.97 MBytes   13ms
[  5]   9.00-10.00  sec   238 MBytes  2.00 Gbits/sec    2   2.25 MBytes   9ms
- - - - - - - - - - - - - - - - - - - - - - - - -
[ ID] Interval           Transfer     Bitrate         Retr
[  5]   0.00-10.00  sec  2.32 GBytes  1.99 Gbits/sec  185             sender
[  5]   0.00-10.00  sec  2.32 GBytes  1.99 Gbits/sec                  receiver

iperf Done.
```

**下载测试 (路由器→客户端)**
```
~ iperf3-darwin -c 10.0.2.1 -p 5201 -t 10 -R
Connecting to host 10.0.2.1, port 5201
Reverse mode, remote host 10.0.2.1 is sending
[  5] local 10.0.2.117 port 53339 connected to 10.0.2.1 port 5201
[ ID] Interval           Transfer     Bitrate         Rwnd
[  5]   0.00-1.00   sec   230 MBytes  1.93 Gbits/sec  1.86 MBytes
[  5]   1.00-2.00   sec   232 MBytes  1.95 Gbits/sec  1.86 MBytes
[  5]   2.00-3.00   sec   231 MBytes  1.94 Gbits/sec  1.86 MBytes
[  5]   3.00-4.00   sec   232 MBytes  1.95 Gbits/sec  1.86 MBytes
[  5]   4.00-5.00   sec   232 MBytes  1.95 Gbits/sec  1.86 MBytes
[  5]   5.00-6.00   sec   232 MBytes  1.95 Gbits/sec  1.86 MBytes
[  5]   6.00-7.00   sec   231 MBytes  1.94 Gbits/sec  1.86 MBytes
[  5]   7.00-8.00   sec   232 MBytes  1.94 Gbits/sec  1.83 MBytes
[  5]   8.00-9.00   sec   232 MBytes  1.95 Gbits/sec  1.86 MBytes
[  5]   9.00-10.00  sec   232 MBytes  1.95 Gbits/sec  1.86 MBytes
- - - - - - - - - - - - - - - - - - - - - - - - -
[ ID] Interval           Transfer     Bitrate         Retr
[  5]   0.00-10.00  sec  2.26 GBytes  1.94 Gbits/sec    1             sender
[  5]   0.00-10.00  sec  2.26 GBytes  1.94 Gbits/sec                  receiver

iperf Done.
```

</details>

## 构建方法

```bash
# 一键编译（保留现有配置）
./build.sh all

# 重置配置后编译
./build.sh reset-config r2s
./build.sh all

# 完全重新编译（清理后编译）
./build.sh rebuild

# 仅重新编译内核（修改内核配置后使用）
./build.sh kernel-rebuild
```

### 所有命令

| 命令 | 说明 |
|------|------|
| `all [设备]` | 一键编译：更新 feeds + 编译（保留现有 .config） |
| `reset-config <设备>` | 重置 .config（r2s 或 rv2） |
| `feeds` | 更新并安装所有 feeds |
| `menu` | 打开 menuconfig |
| `build [选项]` | 开始编译 |
| `rebuild [设备]` | 深度清理后重新编译 |
| `kernel-rebuild` | 清理并重新编译内核 |
| `clean` | 清理构建产物 |
| `dirclean` | 深度清理（保留下载） |
| `saveconfig` | 保存当前配置到 defconfig |

## 固件位置

编译完成后，固件位于：
```
bin/targets/ky/riscv64/
```

## 致谢

- [ImmortalWrt](https://github.com/immortalwrt/immortalwrt)
- [OpenWrt](https://openwrt.org)
