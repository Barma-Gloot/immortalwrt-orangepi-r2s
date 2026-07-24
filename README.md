# ImmortalWrt for Orange Pi R2S

*[English](#english) | [Русский](#русский)*

---

<a name="english"></a>
## English

A custom **ImmortalWrt** firmware for the **Orange Pi R2S (RISC-V KY X1)**, based on [ImmortalWrt](https://github.com/immortalwrt/immortalwrt), forked from [naizhao/immortalwrt-orangepi-r2s](https://github.com/naizhao/immortalwrt-orangepi-r2s) (branch `orangepi-r2s-new`).

### Hardware Specifications

- **SoC:** KY X1 (RISC-V) by SpacemiT
- **Kernel:** Linux 6.6.119
- **Network Interfaces:** 2 × RTL8125 (2.5GbE) + 2 × Gigabit Ethernet

### Network Port Layout (this fork)

> This fork uses a different port layout than the upstream default — chosen to match a vendor-style setup with a single LAN bridge.

| Interface | Physical Location | Speed | Role in this fork |
|-----------|-------------------|-------|--------------------|
| eth0 | — | GbE | **WAN** |
| eth1 | — | GbE | LAN (bridged) |
| eth2 | 2.5GbE port | 2.5GbE | LAN (bridged) |
| eth3 | 2.5GbE port, closest to power connector | 2.5GbE | LAN (bridged) |

### Default Configuration

- **LAN IP Address:** `192.168.0.1`
- **Username:** `root`
- **Password:** *(set on first login)*

### Optimizations Inherited From Upstream

#### 1. Network Performance (RTL8125)

- Uses the `kmod-r8125` driver (version **9.016.01-NAPI-RSS**)
- RSS (Receive Side Scaling) enabled — **4 RX queues / 2 TX queues**
- Measured throughput on 2.5GbE ports: ~1.94–2.00 Gbps (see upstream README history for full benchmark logs)

#### 2. CPU Load Optimization

The following kernel features are disabled by default to avoid uninterruptible (`D`-state) `vq0`/`vq1` kernel threads that otherwise keep load average around 2.0 on an idle system:

| Configuration | Description |
|--------------|-------------|
| `CONFIG_POWERVR_ROGUE` | PowerVR GPU driver (not needed for router workloads) |
| `CONFIG_X1_REMOTEPROC` | KY X1 Remote Processor driver |
| `CONFIG_REMOTEPROC` | Remote Processor subsystem |
| `CONFIG_RPMSG` | Remote Processor Messaging subsystem |

<details>
<summary>Re-enabling these features (GPU / coprocessor use)</summary>

```bash
nano target/linux/ky/riscv64/config-6.6
```

Enable:
```text
CONFIG_POWERVR_ROGUE=y
CONFIG_REMOTEPROC=y
CONFIG_REMOTEPROC_CDEV=y
CONFIG_RPMSG=y
CONFIG_RPMSG_CHAR=y
CONFIG_RPMSG_VIRTIO=y
CONFIG_X1_REMOTEPROC=y
```

Then rebuild the kernel:
```bash
./build.sh kernel-rebuild
```

Expect load average to rise by ~2.0 due to the additional kernel threads — this is expected.

</details>

### Changes Made in This Fork

This fork was built to solve a specific problem: the vendor `ky/riscv64` target is not part of upstream OpenWrt and has no prebuilt package repository, so [Nikki](https://github.com/nikkinikki-org/OpenWrt-nikki)/[mihomo](https://github.com/MetaCubeX/mihomo) could not be installed via `opkg` — the required `kmod-inet-diag`, `kmod-nft-socket`, `kmod-dummy` kernel modules are hash-locked to the exact kernel build and no one publishes them for this specific vendor tree. Building a custom image with these modules baked in was the only reliable fix.

1. **TUN/TPROXY infrastructure for Nikki/Mihomo** — the following kmod packages are built into the image so `opkg install luci-app-nikki` succeeds without dependency errors on first boot:
   `kmod-tun`, `kmod-nf-tproxy`, `kmod-nft-tproxy`, `kmod-nf-socket`, `kmod-nft-socket`, `kmod-inet-diag`, `kmod-netlink-diag`, `kmod-dummy`.
   Nikki/mihomo itself is **not** included in the image — it's installed later from the online feed once the board is running, now that its dependencies are satisfied.

2. **`kmod-usb-printer`** — enabled for network printer sharing via p910nd/USB.

3. **Watchdog enabled** — removed `status = "disabled"` and `spa,wdt-disabled` from the `soc/watchdog@d4080000` devicetree node (disabled by default upstream).

4. **`CONFIG_SLUB_DEBUG=y`** — enabled in the kernel config to allow memory-leak diagnostics via `/proc/slabinfo` / `slabtop`.

5. **IPv4 policy routing fix** — upstream `target/linux/ky/riscv64/config-6.6` ships with:
   ```text
   CONFIG_IPV6_MULTIPLE_TABLES=y
   # CONFIG_IP_MULTIPLE_TABLES is not set
   ```
   IPv6 policy routing (multiple routing tables) was enabled but IPv4 was not — a gap in the upstream `ky` target itself, not introduced by any fork. This blocks TPROXY-based routing (`ip rule add fwmark ... table ...`) for IPv4. Fixed by enabling `CONFIG_IP_MULTIPLE_TABLES=y` to match the IPv6 setting.

6. **Localization** — Chinese (`zh-cn`) LuCI translations replaced with Russian (`ru`) translations throughout.

7. **Removed unused proxy/monitoring tools** to keep the image lean: `luci-app-openclash`, `luci-app-passwall`, `luci-app-smartdns`, `luci-app-zerotier`, `luci-app-openvpn`, `luci-app-netdata`, `luci-app-nlbwmon`, `luci-app-upnp`, `luci-app-vnstat2`, `luci-app-watchcat`, `luci-app-cpulimit`, `luci-app-autoreboot`, `luci-app-netspeedtest`, `luci-app-vlmcsd`, and their Chinese-locale packages.

8. **Network configuration overlay** (`files/etc/config/network`) ships with the port layout described above baked in — no manual reconfiguration needed after first boot.

### Building

```bash
# Build everything while preserving the existing configuration
./build.sh all

# Reset to the default configuration before building
./build.sh reset-config r2s
./build.sh all

# Perform a completely clean rebuild
./build.sh rebuild

# Rebuild only the kernel (after modifying kernel configuration)
./build.sh kernel-rebuild

# Save current .config back to defconfigs/opir2s_defconfig
./build.sh saveconfig
```

#### Available Commands

| Command | Description |
|---------|-------------|
| `all [device]` | Update feeds and build while preserving the current `.config`. |
| `reset-config <device>` | Reset `.config` (`r2s` or `rv2`). |
| `feeds` | Update and install all package feeds. |
| `menu` | Launch `menuconfig`. |
| `build [options]` | Start the build process. |
| `rebuild [device]` | Perform a clean rebuild. |
| `kernel-rebuild` | Clean and rebuild only the kernel. |
| `clean` | Remove build artifacts. |
| `dirclean` | Deep clean while preserving downloaded source files. |
| `saveconfig` | Save the current configuration as `defconfig`. |

### Firmware Output

After a successful build, the firmware images can be found in:
```text
bin/targets/ky/riscv64/
```

### GitHub Actions (Release Builds)

1. Open the repository's **Actions** tab.
2. Select **Build R2S Release**.
3. Click **Run workflow**, selecting the branch with your changes.
4. Optional parameters:
   - **release_tag** — Custom release tag (default: `r2s-YYYYMMDD-<run_number>`)
   - **release_name** — Release title
5. The published release includes `*.img*` and `sha256sums`.

`dl/` and `.ccache` are cached between runs to speed up subsequent builds.

### Flashing

The board has no SD card slot — flashing is done over USB in DFU mode via `fastboot`, using either the vendor `KyDevTool.exe` (Windows GUI) or manual `fastboot` commands on Linux. **Use the vendor u-boot/FSBL for the first flash** of a new image; the self-built `u-boot-opensbi.itb` can be tried later once the system is confirmed stable.

### Acknowledgements

- [ImmortalWrt](https://github.com/immortalwrt/immortalwrt)
- [OpenWrt](https://openwrt.org)
- [naizhao/immortalwrt-orangepi-r2s](https://github.com/naizhao/immortalwrt-orangepi-r2s) — original R2S port this fork is based on
- [Nikki](https://github.com/nikkinikki-org/OpenWrt-nikki) / [mihomo](https://github.com/MetaCubeX/mihomo)

---

<a name="русский"></a>
## Русский

Кастомная прошивка **ImmortalWrt** для платы **Orange Pi R2S (RISC-V KY X1)**, основана на [ImmortalWrt](https://github.com/immortalwrt/immortalwrt), форк от [naizhao/immortalwrt-orangepi-r2s](https://github.com/naizhao/immortalwrt-orangepi-r2s) (ветка `orangepi-r2s-new`).

### Характеристики платы

- **SoC:** KY X1 (RISC-V), производитель SpacemiT
- **Ядро:** Linux 6.6.119
- **Сетевые интерфейсы:** 2 × RTL8125 (2.5GbE) + 2 × Gigabit Ethernet

### Раскладка сетевых портов (в этом форке)

> В этом форке используется другая раскладка портов, чем в апстриме по умолчанию — выбрана схема с одним LAN-бриджем, аналогичная вендорской.

| Интерфейс | Физическое расположение | Скорость | Роль в этом форке |
|-----------|--------------------------|----------|---------------------|
| eth0 | — | GbE | **WAN** |
| eth1 | — | GbE | LAN (в бридже) |
| eth2 | порт 2.5GbE | 2.5GbE | LAN (в бридже) |
| eth3 | порт 2.5GbE, ближе к разъёму питания | 2.5GbE | LAN (в бридже) |

### Настройки по умолчанию

- **IP-адрес LAN:** `192.168.0.1`
- **Логин:** `root`
- **Пароль:** *(задаётся при первом входе)*

### Оптимизации, унаследованные от апстрима

#### 1. Производительность сети (RTL8125)

- Используется драйвер `kmod-r8125` (версия **9.016.01-NAPI-RSS**)
- Включён RSS (Receive Side Scaling) — **4 очереди RX / 2 очереди TX**
- Измеренная пропускная способность на портах 2.5GbE: ~1.94–2.00 Гбит/с

#### 2. Оптимизация загрузки CPU

По умолчанию отключены следующие опции ядра — без этого ядерные потоки `vq0`/`vq1` зависают в состоянии `D` (непрерываемое ожидание), из-за чего `load average` держится около 2.0 даже на простаивающей системе:

| Опция | Описание |
|-------|----------|
| `CONFIG_POWERVR_ROGUE` | Драйвер GPU PowerVR (не нужен для роутера) |
| `CONFIG_X1_REMOTEPROC` | Драйвер сопроцессора KY X1 |
| `CONFIG_REMOTEPROC` | Подсистема Remote Processor |
| `CONFIG_RPMSG` | Подсистема обмена сообщениями с сопроцессором |

<details>
<summary>Как включить обратно (для GPU / сопроцессора)</summary>

```bash
nano target/linux/ky/riscv64/config-6.6
```

Включить:
```text
CONFIG_POWERVR_ROGUE=y
CONFIG_REMOTEPROC=y
CONFIG_REMOTEPROC_CDEV=y
CONFIG_RPMSG=y
CONFIG_RPMSG_CHAR=y
CONFIG_RPMSG_VIRTIO=y
CONFIG_X1_REMOTEPROC=y
```

Затем пересобрать ядро:
```bash
./build.sh kernel-rebuild
```

После этого `load average` вырастет примерно на 2.0 из-за дополнительных ядерных потоков — это ожидаемо.

</details>

### Изменения, внесённые в этом форке

Форк создан для решения конкретной проблемы: вендорский таргет `ky/riscv64` не входит в апстрим OpenWrt и не имеет пакетного репозитория, поэтому [Nikki](https://github.com/nikkinikki-org/OpenWrt-nikki)/[mihomo](https://github.com/MetaCubeX/mihomo) не устанавливались через `opkg` — нужные модули ядра `kmod-inet-diag`, `kmod-nft-socket`, `kmod-dummy` жёстко привязаны к точному хэшу сборки ядра, и под конкретно этот вендорский таргет их никто не публикует. Единственное надёжное решение — собрать собственный образ с этими модулями внутри.

1. **Инфраструктура TUN/TPROXY для Nikki/Mihomo** — в образ включены следующие kmod-пакеты, чтобы `opkg install luci-app-nikki` проходил без ошибок зависимостей сразу после первой загрузки:
   `kmod-tun`, `kmod-nf-tproxy`, `kmod-nft-tproxy`, `kmod-nf-socket`, `kmod-nft-socket`, `kmod-inet-diag`, `kmod-netlink-diag`, `kmod-dummy`.
   Сам Nikki/mihomo в образ **не включён** — устанавливается позже из онлайн-фида уже на работающей плате, когда все его зависимости уже удовлетворены.

2. **`kmod-usb-printer`** — включён для расшаривания принтера по сети через p910nd/USB.

3. **Включён watchdog** — из devicetree-узла `soc/watchdog@d4080000` убраны `status = "disabled"` и `spa,wdt-disabled` (в апстриме watchdog отключён по умолчанию).

4. **`CONFIG_SLUB_DEBUG=y`** — включено в конфиге ядра для диагностики утечек памяти через `/proc/slabinfo` / `slabtop`.

5. **Фикс policy routing для IPv4** — в апстримном `target/linux/ky/riscv64/config-6.6`:
   ```text
   CONFIG_IPV6_MULTIPLE_TABLES=y
   # CONFIG_IP_MULTIPLE_TABLES is not set
   ```
   Policy routing (множественные таблицы маршрутизации) было включено для IPv6, но не для IPv4 — это недоработка самого апстримного таргета `ky`, а не привнесённая каким-либо форком. Из-за этого не работает TPROXY-маршрутизация (`ip rule add fwmark ... table ...`) для IPv4. Исправлено включением `CONFIG_IP_MULTIPLE_TABLES=y` по аналогии с IPv6.

6. **Локализация** — китайские (`zh-cn`) переводы LuCI везде заменены на русские (`ru`).

7. **Убраны неиспользуемые прокси/мониторинговые инструменты** для облегчения образа: `luci-app-openclash`, `luci-app-passwall`, `luci-app-smartdns`, `luci-app-zerotier`, `luci-app-openvpn`, `luci-app-netdata`, `luci-app-nlbwmon`, `luci-app-upnp`, `luci-app-vnstat2`, `luci-app-watchcat`, `luci-app-cpulimit`, `luci-app-autoreboot`, `luci-app-netspeedtest`, `luci-app-vlmcsd` и их китайские локализации.

8. **Оверлей сетевой конфигурации** (`files/etc/config/network`) уже содержит описанную выше раскладку портов — ручная настройка после первой загрузки не требуется.

### Сборка

```bash
# Полная сборка с сохранением текущего .config
./build.sh all

# Сброс конфига к дефолтному перед сборкой
./build.sh reset-config r2s
./build.sh all

# Полная пересборка с нуля (dirclean + all)
./build.sh rebuild

# Пересборка только ядра (после правки конфига ядра)
./build.sh kernel-rebuild

# Сохранить текущий .config обратно в defconfigs/opir2s_defconfig
./build.sh saveconfig
```

#### Доступные команды

| Команда | Описание |
|---------|----------|
| `all [устройство]` | Обновить feeds и собрать, сохраняя текущий `.config`. |
| `reset-config <устройство>` | Сбросить `.config` (`r2s` или `rv2`). |
| `feeds` | Обновить и установить все feeds. |
| `menu` | Открыть `menuconfig`. |
| `build [опции]` | Запустить сборку. |
| `rebuild [устройство]` | Полная пересборка с очисткой. |
| `kernel-rebuild` | Очистить и пересобрать только ядро. |
| `clean` | Удалить артефакты сборки. |
| `dirclean` | Глубокая очистка с сохранением загруженных исходников. |
| `saveconfig` | Сохранить текущий конфиг как `defconfig`. |

### Результат сборки

После успешной сборки образы находятся здесь:
```text
bin/targets/ky/riscv64/
```

### GitHub Actions (сборка релизов)

1. Открыть вкладку **Actions** в репозитории.
2. Выбрать **Build R2S Release**.
3. Нажать **Run workflow**, выбрав ветку со своими изменениями.
4. Необязательные параметры:
   - **release_tag** — свой тег релиза (по умолчанию `r2s-ГГГГММДД-<номер_запуска>`)
   - **release_name** — заголовок релиза
5. В опубликованный релиз попадают `*.img*` и `sha256sums`.

Директории `dl/` и `.ccache` кэшируются между запусками для ускорения последующих сборок.

### Прошивка

У платы нет слота для SD-карты — прошивка выполняется через USB в режиме DFU через `fastboot`, либо вендорским `KyDevTool.exe` (GUI под Windows), либо вручную командами `fastboot` в Linux. **Для первой прошивки нового образа использовать вендорский u-boot/FSBL** — собственный `u-boot-opensbi.itb` можно попробовать позже, когда система уже стабильно работает.

### Благодарности

- [ImmortalWrt](https://github.com/immortalwrt/immortalwrt)
- [OpenWrt](https://openwrt.org)
- [naizhao/immortalwrt-orangepi-r2s](https://github.com/naizhao/immortalwrt-orangepi-r2s) — оригинальный порт под R2S, на котором основан этот форк
- [Nikki](https://github.com/nikkinikki-org/OpenWrt-nikki) / [mihomo](https://github.com/MetaCubeX/mihomo)
