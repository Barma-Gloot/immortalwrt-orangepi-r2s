# ImmortalWrt for Orange Pi R2S

基于 [ImmortalWrt](https://github.com/immortalwrt/immortalwrt) 的 Orange Pi R2S (RISC-V KY X1) 定制固件。

## 硬件信息

- **SoC**: 进迭时空 KY X1 (RISC-V)
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

- 禁用 GPU (PowerVR) 驱动，避免 vq0/vq1 内核线程导致的高负载

### 3. 性能测试

iperf3 测试结果（2.5G 网口）：

| 方向 | 速率 |
|------|------|
| 上传 (客户端→路由器) | **1.87 Gbps** |
| 下载 (路由器→客户端) | **1.94 Gbps** |

## 构建方法

```bash
# 一键编译（保留现有配置）
./build.sh all

# 重置配置后编译
./build.sh reset-config r2s
./build.sh all

# 其他命令
./build.sh feeds          # 更新 feeds
./build.sh menu           # 打开 menuconfig
./build.sh build          # 仅编译
./build.sh saveconfig     # 保存当前配置
```

## 固件位置

编译完成后，固件位于：
```
bin/targets/ky/riscv64/
```

## 致谢

- [ImmortalWrt](https://github.com/immortalwrt/immortalwrt)
- [OpenWrt](https://openwrt.org)
