#!/bin/bash
# Orange Pi R2S 构建脚本

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

# 获取 CPU 核心数
NPROC=$(nproc)

usage() {
    echo "用法: $0 <命令> [选项]"
    echo ""
    echo "命令:"
    echo "  all [设备]        - 一键完成: feeds更新 + 编译 (保留现有 .config)"
    echo "  reset-config <设备> - 重置配置，会覆盖 .config (r2s 或 rv2)"
    echo "  feeds             - 更新并安装所有 feeds"
    echo "  feeds-update      - 仅更新 feeds (不安装)"
    echo "  feeds-install     - 仅安装 feeds (不更新)"
    echo "  menu              - 打开 menuconfig"
    echo "  build [选项]      - 开始编译 (默认 -j$NPROC)"
    echo "  download          - 仅下载所有源码"
    echo "  clean             - 清理构建产物"
    echo "  dirclean          - 深度清理 (保留下载)"
    echo "  saveconfig        - 保存当前配置到 defconfig"
    echo ""
    echo "示例:"
    echo "  $0 all             - 一键编译 Orange Pi R2S"
    echo "  $0 all rv2         - 一键编译 Orange Pi RV2"
    echo "  $0 build           - 使用 $NPROC 线程编译"
    echo "  $0 build -j4 V=s   - 4线程详细编译"
    echo "  $0 feeds           - 更新并安装 feeds"
}

# 更新 feeds
update_feeds() {
    echo "=============================="
    echo "更新 feeds..."
    echo "=============================="
    ./scripts/feeds update -a
    echo ""
    echo "=============================="
    echo "安装 feeds..."
    echo "=============================="
    ./scripts/feeds install -a
    echo "Feeds 更新完成！"
}

# 加载设备配置
config_device() {
    local device="$1"
    case "$device" in
        r2s|R2S)
            echo "加载 Orange Pi R2S 配置..."
            cp defconfigs/opir2s_defconfig .config
            ;;
        rv2|RV2)
            echo "加载 Orange Pi RV2 配置..."
            cp defconfigs/ky_defconfig .config
            ;;
        *)
            echo "错误: 未知设备 '$device'"
            echo "支持的设备: r2s, rv2"
            exit 1
            ;;
    esac
    make defconfig
    echo "配置完成！"
}

# 更新版本号
update_version() {
    local build_date=$(date +%Y%m%d)
    local git_rev=$(./scripts/getver.sh)
    local version_code="${build_date}-${git_rev}"

    echo "=============================="
    echo "更新版本信息:"
    echo "  VERSION_NUMBER: 24.10"
    echo "  VERSION_CODE:   $version_code"
    echo "=============================="

    # 设置固定版本号
    sed -i "s/CONFIG_VERSION_NUMBER=.*/CONFIG_VERSION_NUMBER=\"24.10\"/" .config
    # 设置版本代码（包含构建日期和git修订）
    sed -i "s/CONFIG_VERSION_CODE=.*/CONFIG_VERSION_CODE=\"$version_code\"/" .config

    # 同步更新 defconfigs
    sed -i "s/CONFIG_VERSION_NUMBER=.*/CONFIG_VERSION_NUMBER=\"24.10\"/" defconfigs/config 2>/dev/null || true
    sed -i "s/CONFIG_VERSION_CODE=.*/CONFIG_VERSION_CODE=\"$version_code\"/" defconfigs/config 2>/dev/null || true
}

# 保存配置
save_config() {
    echo "保存配置到 defconfigs/opir2s_defconfig..."
    ./scripts/diffconfig.sh > defconfigs/opir2s_defconfig
    echo "配置已保存！"
}

# 开始编译
do_build() {
    local args="$@"

    # 如果没有指定 -j 参数，自动添加
    if [[ ! "$args" =~ "-j" ]]; then
        args="-j$NPROC $args"
    fi

    update_version

    echo "=============================="
    echo "开始编译 (make $args)"
    echo "=============================="

    local start_time=$(date +%s)
    local build_status=0

    # 使用 pipefail 确保能捕获 make 的退出码
    set -o pipefail
    make $args 2>&1 | tee build.log || build_status=$?
    set +o pipefail

    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    local minutes=$((duration / 60))
    local seconds=$((duration % 60))

    echo "=============================="
    if [ $build_status -eq 0 ]; then
        echo "编译成功！用时: ${minutes}分${seconds}秒"
    else
        echo "编译失败！用时: ${minutes}分${seconds}秒"
        echo "请查看 build.log 或运行: make -j1 V=s"
    fi
    echo "日志已保存到: build.log"
    echo "=============================="

    return $build_status
}

# 一键编译
do_all() {
    local device="${1:-r2s}"

    echo "=============================================="
    echo "  一键编译: $device"
    echo "=============================================="
    echo ""

    update_feeds
    echo ""

    # 如果 .config 已存在，跳过配置覆盖
    if [ -f .config ]; then
        echo "检测到 .config 已存在，跳过配置覆盖"
        echo "如需重置配置，请运行: ./build.sh reset-config $device"
    else
        config_device "$device"
    fi
    echo ""

    if do_build; then
        echo ""
        echo "=============================================="
        echo "  编译成功！固件位置:"
        echo "  bin/targets/ky/riscv64/"
        echo "=============================================="
    else
        echo ""
        echo "=============================================="
        echo "  编译失败！请检查错误信息"
        echo "=============================================="
        exit 1
    fi
}

case "$1" in
    all)
        do_all "$2"
        ;;
    reset-config)
        [ -z "$2" ] && { echo "错误: 请指定设备 (r2s 或 rv2)"; exit 1; }
        config_device "$2"
        ;;
    feeds)
        update_feeds
        ;;
    feeds-update)
        echo "更新 feeds..."
        ./scripts/feeds update -a
        ;;
    feeds-install)
        echo "安装 feeds..."
        ./scripts/feeds install -a
        ;;
    menu)
        make menuconfig
        ;;
    build)
        shift
        do_build "$@"
        ;;
    download)
        echo "下载所有源码..."
        make download -j$NPROC
        ;;
    clean)
        echo "清理构建产物..."
        make clean
        ;;
    dirclean)
        echo "深度清理..."
        make dirclean
        ;;
    saveconfig)
        save_config
        ;;
    -h|--help|help)
        usage
        ;;
    *)
        usage
        ;;
esac
