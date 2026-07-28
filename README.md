# ImmortalWrt for Orange Pi R2S

*[English](#english) | [Русский](#русский)*

---

<a name="english"></a>
## English

A custom **ImmortalWrt** firmware for the **Orange Pi R2S (RISC-V KY X1)**, based on [ImmortalWrt](https://github.com/immortalwrt/immortalwrt), forked from [naizhao/immortalwrt-orangepi-r2s](https://github.com/naizhao/immortalwrt-orangepi-r2s) (branch `orangepi-r2s-new`).

### Hardware Specifications

- **SoC:** KY X1 (RISC-V) by SpacemiT
- **Kernel:** Linux 6.6.138
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
- **LuCI language:** Russian (Chinese removed entirely, see below)

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

This fork was built to solve a specific problem: the vendor `ky/riscv64` target is not part of upstream OpenWrt and has no prebuilt package repository, so **TPROXY mode did not work** in [Nikki](https://github.com/nikkinikki-org/OpenWrt-nikki)/[mihomo](https://github.com/MetaCubeX/mihomo) — the required `kmod-inet-diag`, `kmod-nft-socket`, `kmod-dummy` kernel modules are hash-locked to the exact kernel build and no one publishes them for this specific vendor tree, so they couldn't be installed via `opkg` after the fact. Building a custom image with these modules baked in was the only reliable fix.

#### Kernel & devicetree

1. **TUN/TPROXY infrastructure for Nikki/Mihomo** — the following kmod packages are built into the image so `opkg install luci-app-nikki` succeeds without dependency errors on first boot:
   `kmod-tun`, `kmod-nf-tproxy`, `kmod-nft-tproxy`, `kmod-nf-socket`, `kmod-nft-socket`, `kmod-inet-diag`, `kmod-netlink-diag`, `kmod-dummy`.
   Nikki/mihomo itself is **not** included in the image — it's installed later from the online feed once the board is running, now that its dependencies are satisfied.

2. **`kmod-usb-printer`** — enabled for network printer sharing via p910nd/USB.

3. **Watchdog enabled** — removed `status = "disabled"` and `spa,wdt-disabled` from the `soc/watchdog@d4080000` devicetree node (disabled by default upstream). Shipped as patch `0024-enable-watchdog.patch`.

4. **`CONFIG_SLUB_DEBUG=y`** — enabled in the kernel config to allow memory-leak diagnostics via `/proc/slabinfo` / `slabtop`.

5. **IPv4 policy routing fix** — upstream `target/linux/ky/riscv64/config-6.6` ships with:
   ```text
   CONFIG_IPV6_MULTIPLE_TABLES=y
   # CONFIG_IP_MULTIPLE_TABLES is not set
   ```
   IPv6 policy routing (multiple routing tables) was enabled but IPv4 was not — a gap in the upstream `ky` target itself, not introduced by any fork. This blocks TPROXY-based routing (`ip rule add fwmark ... table ...`) for IPv4. Fixed by enabling `CONFIG_IP_MULTIPLE_TABLES=y` to match the IPv6 setting.

#### Updated libraries

The following libraries were updated past their upstream OpenWrt/ImmortalWrt-pinned versions, each verified with a full rebuild against this target:

| Package | From | To | Reason |
|---|---|---|---|
| `openssl` | 3.0.18 | **3.6.3** | Latest stable; see riscv64 acceleration flags below. Required adapting 4 of the 8 OpenWrt-carried patches to the new upstream source layout (`Configure`, `ssl_ciph.c`, `ssl.h.in`, `e_devcrypto.c`). |
| `procd` / `procd-ujail` | snapshot 2024-12-22 | **snapshot 2026-03-14** | Fixes an out-of-bounds write in `cgroups_apply()`, a use-after-free in the per-instance `set_data` handler, and the hotplug-dispatch `PATH` filter bypass (CVE-2026-30874). |
| `ustream-ssl` (`libustream-openssl`) | snapshot 2024-07-28 | **snapshot 2026-03-01** | Fixes a use-after-free crash under high load and optimizes `BIO_METHOD` lifecycle. |
| `pcre2` | 10.42 | **10.45** | Routine upstream bump. |
| `libcap` | 2.69 | **2.75** | Fixes CVE-2026-4878. |
| `libunistring` | 1.2 | **1.3** | Routine upstream bump. |

**OpenSSL RISC-V acceleration** — this fork adds a `riscv64`-specific block to `package/libs/openssl/Makefile`:
```makefile
ifeq ($(CONFIG_riscv64),y)
  OPENSSL_OPTIONS += enable-ec_nistp_64_gcc_128
  TARGET_CFLAGS += -DOSSL_RISCV_HWPROBE -D__NR_riscv_hwprobe=258
endif
```
The KY X1 has no crypto extensions, so `-DOPENSSL_PREFER_CHACHA_OVER_GCM` (already present upstream) is combined with these flags — ChaCha20-Poly1305 runs roughly 3× faster than AES on this CPU without hardware acceleration.

Libraries explicitly **not** touched, with reasoning: `lua` (5.1 → 5.4 is a breaking language change; OpenWrt/LuCI depend on 5.1 semantics), `nettle` (no riscv64 asm path, negligible gain), `libnftnl` (tightly coupled to the in-tree nftables/kernel version), `gmp`/`libpcap`/`libmnl`/`bzip2` (already at latest upstream).

#### Toolchain

6. **GDB disabled** — the bundled toolchain GDB 15.2 fails to link against this environment's iconv/gnulib (`undefined reference to convert_between_encodings` and related symbols) and isn't needed for this build. Since `toolchain/Config.in` hard-defaults `GDB` to `y` whenever an external toolchain isn't used (with no way to override it from `.config`), the default was patched directly: `default y if !EXTERNAL_TOOLCHAIN` → `default n`.

#### Localization

7. **Chinese removed entirely, Russian set as default** — this required patching three separate layers, since a single `.config` edit doesn't survive `make defconfig`:
   - `CONFIG_LUCI_LANG_zh_Hans` → disabled, `CONFIG_LUCI_LANG_ru` → enabled (this is what actually drives per-app `-zh-cn` language package generation).
   - The `default-settings-chn` package (which forces `+luci-i18n-base-zh-cn` via `DEPENDS`) is disabled.
   - The line `default-settings-chn \` was removed from `DEFAULT_PACKAGES.tweak` in `include/target.mk`, where it was unconditionally forced for every build on this tree regardless of target or profile.

8. **Removed unused proxy/monitoring tools** to keep the image lean: `luci-app-openclash`, `luci-app-passwall`, `luci-app-smartdns`, `luci-app-zerotier`, `luci-app-openvpn`, `luci-app-netdata`, `luci-app-nlbwmon`, `luci-app-upnp`, `luci-app-vnstat2`, `luci-app-watchcat`, `luci-app-cpulimit`, `luci-app-autoreboot`, `luci-app-netspeedtest`, `luci-app-vlmcsd`, and their locale packages.

9. **Network configuration overlay** (`files/etc/config/network`) ships with the port layout described above baked in — no manual reconfiguration needed after first boot.

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

> **Note:** after any `.config` edit, prefer `scripts/config/conf --oldconfig Config.in` over a raw `sed` + `make defconfig` if the option has a Kconfig `default` — plain `.config` edits are silently reverted on the next config pass unless a real Kconfig tool records the change as user-set.

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

### Replacing the Vendor Firmware (Quick Guide)

If the board is currently running the stock vendor OpenWrt 24.10.0 image and you want to switch to this build:

1. **Get the vendor factory files.** From the official Orange Pi R2S downloads page → **Official Tools** → download the archive containing **"Linux image burning tool - KyDevTool"**. It contains `KyDevTool.exe`, `fastboot.exe`, and a `factory/` folder with `FSBL.bin`, `u-boot.itb`, `partition_universal.json`, `bootinfo_emmc.bin`, `SPA3607.bin`.
2. **Build or download this fork's image** — the sysupgrade `.img.gz` from `bin/targets/ky/riscv64/` (or from a GitHub Actions release), then unpack the `.gz`.
3. **Put the board into DFU/fastboot mode:** power off → connect a USB-A "male-to-male" cable to the **USB 2.0** port (not USB 3.0) → hold the **BOOT** button → connect power via USB-C → wait 2–3 seconds → release BOOT.
4. **Flash using `KyDevTool.exe`** (Windows, recommended): run as administrator → **Scan Devices** → point FSBL/u-boot/GPT/bootinfo fields to the files in `factory/` (use `bootinfo_emmc.bin`, not `_sd`/`_spinand`/`_spinor`) → point the image field to your unpacked `.img` → **Upgrade**.
   Alternatively, on Linux with `fastboot`:
   ```bash
   sudo fastboot stage FSBL.bin && sudo fastboot continue
   sudo fastboot stage u-boot.itb && sudo fastboot continue
   sudo fastboot flash gpt partition_universal.json
   sudo fastboot flash bootinfo bootinfo_emmc.bin
   sudo fastboot flash fsbl FSBL.bin
   sudo fastboot flash emmc /path/to/your-image.img
   ```
5. **Reboot** — disconnect the USB-A cable, reconnect power, and verify the board comes up with LAN on `192.168.0.1`.

> Always use the **vendor** FSBL/u-boot for this first flash, not the self-built `u-boot-opensbi.itb` — it's the safer, tested path for this specific board revision.

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
- **Ядро:** Linux 6.6.138
- **Сетевые интерфейсы:** 2 × RTL8125 (2.5GbE) + 2 × Gigabit Ethernet

### Раскладка сетевых портов (в этом форке)

> В этом форке используется другая раскладка портов, чем в апстриме по умолчанию — выбрана схема с одним LAN-бриджем, аналогичная вендорской.

| Интерфейс | Физическое расположение | Скорость | Роль в этом форке |
|-----------|--------------------------|----------|---------------------|
| eth0 | порт 1GbE | GbE | **WAN** |
| eth1 | порт 1GbE | GbE | LAN (в бридже) |
| eth2 | порт 2.5GbE | 2.5GbE | LAN (в бридже) |
| eth3 | порт 2.5GbE, ближе к разъёму питания | 2.5GbE | LAN (в бридже) |

### Настройки по умолчанию

- **IP-адрес LAN:** `192.168.0.1`
- **Логин:** `root`
- **Пароль:** *(задаётся при первом входе)*
- **Язык LuCI:** русский (китайский убран полностью, см. ниже)

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

Форк создан для решения конкретной проблемы: вендорский таргет `ky/riscv64` не входит в апстрим OpenWrt и не имеет пакетного репозитория, поэтому **в [Nikki](https://github.com/nikkinikki-org/OpenWrt-nikki)/[mihomo](https://github.com/MetaCubeX/mihomo) не работал режим TPROXY** — нужные модули ядра `kmod-inet-diag`, `kmod-nft-socket`, `kmod-dummy` жёстко привязаны к точному хэшу сборки ядра, и под конкретно этот вендорский таргет их никто не публикует, поэтому их не получалось доустановить через `opkg`. Единственное надёжное решение — собрать собственный образ с этими модулями внутри.

#### Ядро и devicetree

1. **Инфраструктура TUN/TPROXY для Nikki/Mihomo** — в образ включены следующие kmod-пакеты, чтобы `opkg install luci-app-nikki` проходил без ошибок зависимостей сразу после первой загрузки:
   `kmod-tun`, `kmod-nf-tproxy`, `kmod-nft-tproxy`, `kmod-nf-socket`, `kmod-nft-socket`, `kmod-inet-diag`, `kmod-netlink-diag`, `kmod-dummy`.
   Сам Nikki/mihomo в образ **не включён** — устанавливается позже из онлайн-фида уже на работающей плате, когда все его зависимости уже удовлетворены.

2. **`kmod-usb-printer`** — включён для расшаривания принтера по сети через p910nd/USB.

3. **Включён watchdog** — из devicetree-узла `soc/watchdog@d4080000` убраны `status = "disabled"` и `spa,wdt-disabled` (в апстриме watchdog отключён по умолчанию). Оформлено как патч `0024-enable-watchdog.patch`.

4. **`CONFIG_SLUB_DEBUG=y`** — включено в конфиге ядра для диагностики утечек памяти через `/proc/slabinfo` / `slabtop`.

5. **Фикс policy routing для IPv4** — в апстримном `target/linux/ky/riscv64/config-6.6`:
   ```text
   CONFIG_IPV6_MULTIPLE_TABLES=y
   # CONFIG_IP_MULTIPLE_TABLES is not set
   ```
   Policy routing (множественные таблицы маршрутизации) было включено для IPv6, но не для IPv4 — это недоработка самого апстримного таргета `ky`, а не привнесённая каким-либо форком. Из-за этого не работает TPROXY-маршрутизация (`ip rule add fwmark ... table ...`) для IPv4. Исправлено включением `CONFIG_IP_MULTIPLE_TABLES=y` по аналогии с IPv6.

#### Обновлённые библиотеки

Следующие библиотеки обновлены сверх версий, зафиксированных в апстриме OpenWrt/ImmortalWrt, каждая проверена полной пересборкой под этот таргет:

| Пакет | Было | Стало | Причина |
|---|---|---|---|
| `openssl` | 3.0.18 | **3.6.3** | Актуальная стабильная версия; см. флаги ускорения под riscv64 ниже. Потребовало адаптации 4 из 8 патчей OpenWrt под новую структуру исходников апстрима (`Configure`, `ssl_ciph.c`, `ssl.h.in`, `e_devcrypto.c`). |
| `procd` / `procd-ujail` | снапшот 2024-12-22 | **снапшот 2026-03-14** | Исправляет запись за пределы буфера в `cgroups_apply()`, use-after-free в обработчике `set_data` для инстансов сервисов, и обход фильтра `PATH` в hotplug-dispatch (CVE-2026-30874). |
| `ustream-ssl` (`libustream-openssl`) | снапшот 2024-07-28 | **снапшот 2026-03-01** | Исправляет use-after-free при высокой нагрузке, оптимизирует жизненный цикл `BIO_METHOD`. |
| `pcre2` | 10.42 | **10.45** | Плановое обновление апстрима. |
| `libcap` | 2.69 | **2.75** | Закрывает CVE-2026-4878. |
| `libunistring` | 1.2 | **1.3** | Плановое обновление апстрима. |

**Ускорение OpenSSL под RISC-V** — в этом форке добавлен riscv64-специфичный блок в `package/libs/openssl/Makefile`:
```makefile
ifeq ($(CONFIG_riscv64),y)
  OPENSSL_OPTIONS += enable-ec_nistp_64_gcc_128
  TARGET_CFLAGS += -DOSSL_RISCV_HWPROBE -D__NR_riscv_hwprobe=258
endif
```
У KY X1 нет крипто-расширений, поэтому эти флаги используются вместе с `-DOPENSSL_PREFER_CHACHA_OVER_GCM` (уже присутствует в апстриме) — ChaCha20-Poly1305 работает примерно в 3 раза быстрее AES на этом процессоре без аппаратного ускорения.

Библиотеки, которые сознательно **не тронуты**, с обоснованием: `lua` (переход 5.1 → 5.4 — несовместимое изменение языка; OpenWrt/LuCI зависят от семантики 5.1), `nettle` (нет ассемблерных путей под riscv64, выигрыш незначителен), `libnftnl` (жёстко привязан к версии nftables/ядра в этом дереве), `gmp`/`libpcap`/`libmnl`/`bzip2` (уже последние версии апстрима).

#### Toolchain

6. **Отключён GDB** — встроенный в toolchain GDB 15.2 не линкуется в этом окружении из-за проблем с iconv/gnulib (`undefined reference to convert_between_encodings` и связанные символы), и не нужен для этой сборки. Поскольку `toolchain/Config.in` жёстко задаёт `default y if !EXTERNAL_TOOLCHAIN` для GDB без возможности переопределить это через `.config`, дефолт исправлен напрямую в исходнике: `default y if !EXTERNAL_TOOLCHAIN` → `default n`.

#### Локализация

7. **Китайский убран полностью, русский — язык по умолчанию** — потребовало правки трёх независимых уровней, так как обычная правка `.config` не переживает `make defconfig`:
   - `CONFIG_LUCI_LANG_zh_Hans` → выключено, `CONFIG_LUCI_LANG_ru` → включено (именно эта опция реально управляет генерацией `-zh-cn`-пакетов локализации для каждого установленного приложения).
   - Пакет `default-settings-chn` (форсирующий `+luci-i18n-base-zh-cn` через `DEPENDS`) отключён.
   - Строка `default-settings-chn \` удалена из `DEFAULT_PACKAGES.tweak` в `include/target.mk`, где она была безусловно навязана для любой сборки на этом дереве, независимо от таргета или профиля.

8. **Убраны неиспользуемые прокси/мониторинговые инструменты** для облегчения образа: `luci-app-openclash`, `luci-app-passwall`, `luci-app-smartdns`, `luci-app-zerotier`, `luci-app-openvpn`, `luci-app-netdata`, `luci-app-nlbwmon`, `luci-app-upnp`, `luci-app-vnstat2`, `luci-app-watchcat`, `luci-app-cpulimit`, `luci-app-autoreboot`, `luci-app-netspeedtest`, `luci-app-vlmcsd` и их локализации.

9. **Оверлей сетевой конфигурации** (`files/etc/config/network`) уже содержит описанную выше раскладку портов — ручная настройка после первой загрузки не требуется.

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

> **Важно:** после любой правки `.config` для опции с Kconfig-значением `default`, используйте `scripts/config/conf --oldconfig Config.in` вместо простого `sed` + `make defconfig` — прямые правки `.config` молча откатываются при следующем пересчёте конфига, если изменение не зафиксировано через настоящий Kconfig-инструмент как «заданное пользователем».

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

### Замена вендорской прошивки (краткая инструкция)

Если на плате сейчас стоит штатная вендорская прошивка OpenWrt 24.10.0 и вы хотите перейти на эту сборку:

1. **Получить вендорские файлы.** На официальной странице загрузок Orange Pi R2S → раздел **Official Tools** → скачать архив с папкой **«Linux image burning tool - KyDevTool»**. Внутри — `KyDevTool.exe`, `fastboot.exe` и папка `factory/` с `FSBL.bin`, `u-boot.itb`, `partition_universal.json`, `bootinfo_emmc.bin`, `SPA3607.bin`.
2. **Собрать или скачать образ этого форка** — sysupgrade-файл `.img.gz` из `bin/targets/ky/riscv64/` (либо из релиза GitHub Actions), затем распаковать `.gz`.
3. **Перевести плату в режим DFU/fastboot:** выключить питание → подключить USB-A кабель «папа-папа» в порт **USB 2.0** (не USB 3.0) → зажать кнопку **BOOT** → подключить питание через USB-C → подождать 2–3 секунды → отпустить BOOT.
4. **Прошить через `KyDevTool.exe`** (Windows, рекомендуется): запустить от имени администратора → **Scan Devices** → указать пути к FSBL/u-boot/GPT/bootinfo из папки `factory/` (использовать именно `bootinfo_emmc.bin`, не `_sd`/`_spinand`/`_spinor`) → в поле образа указать распакованный `.img` → **Upgrade**.
   Либо через Linux с `fastboot`:
   ```bash
   sudo fastboot stage FSBL.bin && sudo fastboot continue
   sudo fastboot stage u-boot.itb && sudo fastboot continue
   sudo fastboot flash gpt partition_universal.json
   sudo fastboot flash bootinfo bootinfo_emmc.bin
   sudo fastboot flash fsbl FSBL.bin
   sudo fastboot flash emmc /путь/к/вашему-образу.img
   ```
5. **Перезагрузить** — отключить USB-A кабель, переподключить питание, проверить что плата загрузилась и LAN доступен на `192.168.0.1`.

> Для этой первой прошивки всегда использовать **вендорский** FSBL/u-boot, а не собственный `u-boot-opensbi.itb` — это более безопасный, проверенный путь именно для этой ревизии платы.

### Благодарности

- [ImmortalWrt](https://github.com/immortalwrt/immortalwrt)
- [OpenWrt](https://openwrt.org)
- [naizhao/immortalwrt-orangepi-r2s](https://github.com/naizhao/immortalwrt-orangepi-r2s) — оригинальный порт под R2S, на котором основан этот форк
- [Nikki](https://github.com/nikkinikki-org/OpenWrt-nikki) / [mihomo](https://github.com/MetaCubeX/mihomo)
