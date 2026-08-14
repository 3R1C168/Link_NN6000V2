#!/usr/bin/env bash

GITHUB_BASE="https://github.com/"
OPENWRT_PACKAGES_DIR="$BUILD_DIR/feeds/openwrt_packages"

update_golang() {
    if [[ -d ./feeds/packages/lang/golang ]]; then
        \rm -rf ./feeds/packages/lang/golang
        if ! git clone --depth 1 -b $GOLANG_BRANCH $GOLANG_REPO ./feeds/packages/lang/golang; then
            echo "错误：克隆 golang 仓库 $GOLANG_REPO 失败" >&2
            exit 1
        fi
        echo "✓ golang 软件包更新完成"
    fi
}

clone_packages() {
    local name="$1"
    local repo_url="$2"
    local target_dir="$3"
    local sparse_pattern="${4:-}"
    local pre_cmd="${5:-}"
    local post_cmd="${6:-}"
    local move_from="${7:-}"
    local move_to="${8:-}"
    
    if [ -n "$pre_cmd" ]; then
        (cd "$BUILD_DIR" && eval "$pre_cmd") || return 1
    fi
    
    rm -rf "$target_dir" 2>/dev/null || true
    
    if [ -n "$sparse_pattern" ]; then
        if ! git clone --filter=blob:none --no-checkout "$repo_url" "$target_dir"; then
            echo "错误：从 $repo_url 克隆 $name 仓库失败" >&2
            exit 1
        fi
        
        pushd "$target_dir" >/dev/null
        git sparse-checkout init --cone
        if ! git sparse-checkout set $sparse_pattern; then
            echo "错误：稀疏检出 $sparse_pattern 失败" >&2
            popd >/dev/null
            return 1
        fi
        git checkout --quiet
        popd >/dev/null
        
        if [ -n "$move_from" ] && [ -n "$move_to" ]; then
            rm -rf "$move_to" 2>/dev/null || true
            mv "$move_from" "$move_to" || return 1
        fi
    else
        if ! git clone --depth=1 "$repo_url" "$target_dir"; then
            echo "错误：从 $repo_url 克隆 $name 仓库失败" >&2
            exit 1
        fi
    fi
    
    if [ -n "$post_cmd" ]; then
        (cd "$BUILD_DIR" && eval "$post_cmd") || return 1
    fi
    
    echo "✓ $name 克隆完成"
}

install_openwrt_packages() {
    # 注意：本白名单只控制 feeds install（把包链接进 package/feeds/），
    # 是否编进固件由 configs/*.config 的 CONFIG_PACKAGE_* 决定。
    # 已删除插件的条目保留不影响构建（对应的 =n 配置会跳过），
    # 但新增插件（openclash/nikki/mosdns）必须在此列出，否则不会被 install。
    ./scripts/feeds install -p openwrt_packages -f \
        taskd luci-lib-xterm luci-lib-taskd \
        luci-app-store quickstart luci-app-quickstart \
        luci-theme-argon luci-app-argon-config \
        luci-app-adguardhome \
        luci-app-quickfile \
        luci-app-tailscale-community \
        luci-app-openclash \
        luci-app-nikki nikki mihomo-alpha mihomo-meta \
        luci-app-mosdns mosdns v2dat v2ray-geodata
}



clone_adguardhome() {
    clone_packages "luci-app-adguardhome" \
        "${GITHUB_BASE}wzdddyy/luci-app-adguardhome.git" \
        "$OPENWRT_PACKAGES_DIR/luci-app-adguardhome"
}

clone_quickfile() {
    local QUICKFILE_DIR="$OPENWRT_PACKAGES_DIR/luci-app-quickfile"
    local TEMP_DIR="$OPENWRT_PACKAGES_DIR/quickfile-temp"

    clone_packages "luci-app-quickfile" \
        "${GITHUB_BASE}sbwml/luci-app-quickfile.git" \
        "$TEMP_DIR" \
        "luci-app-quickfile quickfile" \
        "" \
        "mkdir -p \"$QUICKFILE_DIR\" && rm -rf \"$QUICKFILE_DIR/luci-app-quickfile\" \"$QUICKFILE_DIR/quickfile\" && mv \"$TEMP_DIR/luci-app-quickfile\" \"$TEMP_DIR/quickfile\" \"$QUICKFILE_DIR/\""

    rm -rf "$TEMP_DIR"
}

remove_attendedsysupgrade() {
    find "$BUILD_DIR/feeds/luci/collections" -name "Makefile" | while read -r makefile; do
        if grep -q "luci-app-attendedsysupgrade" "$makefile"; then
            sed -i "/luci-app-attendedsysupgrade/d" "$makefile"
            echo "Removed luci-app-attendedsysupgrade from $makefile"
        fi
    done
}

clone_luci_tailscale() {
    local TEMP_DIR="$OPENWRT_PACKAGES_DIR/luci-app-tailscale-community-temp"
    local TARGET_DIR="$OPENWRT_PACKAGES_DIR/luci-app-tailscale-community"

    clone_packages "luci-app-tailscale-community" \
        "${GITHUB_BASE}Tokisaki-Galaxy/luci-app-tailscale-community.git" \
        "$TEMP_DIR" \
        "" \
        "" \
        "rm -rf \"$TARGET_DIR\" 2>/dev/null || true; mv \"$TEMP_DIR/luci-app-tailscale-community\" \"$TARGET_DIR\"; rm -rf \"$TEMP_DIR\""
}

# ============================================================
# 以下三个函数为自定义新增：OpenClash / Nikki / MosDNS
# 说明：原项目 feeds 默认不含这三个插件，需手动 clone 注入
# ============================================================

# OpenClash —— Clash 图形界面（社区版），使用 mihomo/clash-meta 内核
# 仓库根目录直接含 luci-app-openclash，整仓 clone 到 feeds 即可
clone_openclash() {
    local TARGET_DIR="$OPENWRT_PACKAGES_DIR/luci-app-openclash"

    clone_packages "luci-app-openclash" \
        "${GITHUB_BASE}vernesong/OpenClash.git" \
        "$TARGET_DIR"
}

# Nikki —— mihomo (clash.meta) 的全新 LuCI 前端，界面现代
# 仓库为"多包聚合"结构：luci-app-nikki / nikki / mihomo-alpha / mihomo-meta
# 整仓 clone 到 feeds 目录后，每个子目录都是独立的编译包
clone_nikki() {
    local TEMP_DIR="$OPENWRT_PACKAGES_DIR/nikki-temp"
    local TARGET_DIR="$OPENWRT_PACKAGES_DIR/nikki-repo"

    # 克隆到临时目录（避免与 feeds install 冲突）
    clone_packages "OpenWrt-nikki" \
        "${GITHUB_BASE}nikkinikki-org/OpenWrt-nikki.git" \
        "$TEMP_DIR"

    # 把仓库内 4 个独立包目录分别移动到 feeds 根，使其可被识别为独立 feed 包
    local pkg
    for pkg in luci-app-nikki nikki mihomo-alpha mihomo-meta; do
        rm -rf "$OPENWRT_PACKAGES_DIR/$pkg" 2>/dev/null || true
        if [ -d "$TEMP_DIR/$pkg" ]; then
            mv "$TEMP_DIR/$pkg" "$OPENWRT_PACKAGES_DIR/$pkg"
        fi
    done

    rm -rf "$TEMP_DIR"
}

# MosDNS —— DNS 分流引擎，配合 geodata 实现国内外 DNS 智能分流
# 依赖说明：
#   - luci-app-mosdns 仓库自带 mosdns core 目录（v5 分支）
#   - 另需 v2ray-geodata 提供 geoip/geosite 数据文件
clone_mosdns() {
    local MOSDNS_DIR="$OPENWRT_PACKAGES_DIR/luci-app-mosdns"
    local GEODATA_DIR="$OPENWRT_PACKAGES_DIR/v2ray-geodata"

    # 克隆 luci-app-mosdns（v5 分支，内含 mosdns core 编译规则）
    rm -rf "$MOSDNS_DIR" 2>/dev/null || true
    if ! git clone --depth 1 -b v5 "${GITHUB_BASE}sbwml/luci-app-mosdns.git" "$MOSDNS_DIR"; then
        echo "错误：克隆 luci-app-mosdns 失败" >&2
        exit 1
    fi

    # geodata 数据包（geoip / geosite），mosdns 启动必需
    rm -rf "$GEODATA_DIR" 2>/dev/null || true
    if ! git clone --depth 1 "${GITHUB_BASE}sbwml/v2ray-geodata.git" "$GEODATA_DIR"; then
        echo "错误：克隆 v2ray-geodata 失败" >&2
        exit 1
    fi

    echo "✓ luci-app-mosdns + v2ray-geodata 克隆完成"
}
