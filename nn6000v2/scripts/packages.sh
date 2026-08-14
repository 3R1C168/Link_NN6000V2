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
    ./scripts/feeds install -p openwrt_packages -f \
        xray-core sing-box trojan-plus naiveproxy shadowsocks-libev v2ray-plugin geoview \
        microsocks tcping chinadns-ng dns2socks resolveip \
        taskd luci-lib-xterm luci-lib-taskd \
        luci-app-store quickstart luci-app-quickstart luci-app-istorex \
        smartdns luci-app-smartdns luci-theme-argon luci-app-argon-config \
        luci-lib-docker luci-app-lucky luci-app-adguardhome luci-app-easytier \
        luci-app-oaf oaf open-app-filter \
        luci-app-diskman luci-app-dockerman luci-app-quickfile luci-app-passwall \
        luci-app-tailscale-community \
        luci-app-openclash \
        luci-app-nikki nikki mihomo-alpha mihomo-meta \
        luci-app-mosdns mosdns v2dat v2ray-geodata
}

clone_passwall() {
    local PASSWALL_LUCI_DIR="$OPENWRT_PACKAGES_DIR/luci-app-passwall"
    local PASSWALL_PACKAGES_DIR="$OPENWRT_PACKAGES_DIR/passwall-packages"
    local TEMP_DIR="$OPENWRT_PACKAGES_DIR/openwrt-passwall-temp"
    local PASSWALL_PKGS_TEMP="$OPENWRT_PACKAGES_DIR/passwall-packages-temp"
    
    clone_packages "luci-app-passwall" \
        "${GITHUB_BASE}Openwrt-Passwall/openwrt-passwall.git" \
        "$TEMP_DIR" \
        "" \
        "" \
        "rm -rf \"$PASSWALL_LUCI_DIR\" 2>/dev/null || true; mv \"$TEMP_DIR/luci-app-passwall\" \"$PASSWALL_LUCI_DIR\"; rm -rf \"$TEMP_DIR\""
    
    rm -rf "$PASSWALL_PACKAGES_DIR" 2>/dev/null || true
    
    clone_packages "passwall-packages" \
        "${GITHUB_BASE}Openwrt-Passwall/openwrt-passwall-packages.git" \
        "$PASSWALL_PKGS_TEMP" \
        "" \
        "" \
        "for pkg in \"$PASSWALL_PKGS_TEMP\"/*; do if [ -d \"\$pkg\" ]; then pkg_name=\$(basename \"\$pkg\"); mv \"\$pkg\" \"$OPENWRT_PACKAGES_DIR/\$pkg_name\"; fi; done; rm -rf \"$PASSWALL_PKGS_TEMP\""
}

clone_lucky() {
    local LUCKY_REPO="${GITHUB_BASE}gdy666/luci-app-lucky.git"
    local LUCKY_DIR="$OPENWRT_PACKAGES_DIR/lucky"
    local LUCI_APP_LUCKY_DIR="$OPENWRT_PACKAGES_DIR/luci-app-lucky"
    local LUCKY_TEMP="$OPENWRT_PACKAGES_DIR/lucky-temp"
    local LUCKI_APP_TEMP="$OPENWRT_PACKAGES_DIR/luci-app-lucky-temp"

    clone_packages "lucky" \
        "$LUCKY_REPO" \
        "$LUCKY_TEMP" \
        "lucky" \
        "" \
        "" \
        "$LUCKY_TEMP/lucky" \
        "$LUCKY_DIR"

    rm -rf "$LUCKY_TEMP"

    clone_packages "luci-app-lucky" \
        "$LUCKY_REPO" \
        "$LUCKI_APP_TEMP" \
        "luci-app-lucky" \
        "" \
        "" \
        "$LUCKI_APP_TEMP/luci-app-lucky" \
        "$LUCI_APP_LUCKY_DIR"

    rm -rf "$LUCKI_APP_TEMP"
    
    local lucky_conf="$LUCKY_DIR/files/luckyuci"
    if [ -f "$lucky_conf" ]; then
        sed -i "s/option enabled '1'/option enabled '0'/g" "$lucky_conf"
        sed -i "s/option logger '1'/option logger '0'/g" "$lucky_conf"
    fi
    
    local version
    version=$(find "$BASE_PATH/patches" -name "lucky_*.tar.gz" -printf "%f\n" | head -n 1 | sed -n 's/^lucky_\(.*\)_Linux.*$/\1/p')
    if [ -z "$version" ]; then
        echo "Warning: 未找到 lucky 补丁文件，跳过更新。" >&2
        return 0
    fi
    
    local makefile_path="$LUCKY_DIR/Makefile"
    if [ ! -f "$makefile_path" ]; then
        echo "Warning: lucky Makefile not found. Skipping." >&2
        return 0
    fi
    
    local patch_line="\\t[ -f \$(TOPDIR)/../nn6000v2/patches/lucky_${version}_Linux_\$(LUCKY_ARCH)_wanji.tar.gz ] && install -Dm644 \$(TOPDIR)/../nn6000v2/patches/lucky_${version}_Linux_\$(LUCKY_ARCH)_wanji.tar.gz \$(PKG_BUILD_DIR)/\$(PKG_NAME)_\$(PKG_VERSION)_Linux_\$(LUCKY_ARCH).tar.gz"
    
    if grep -q "Build/Prepare" "$makefile_path"; then
        sed -i "/Build\\/Prepare/a\\$patch_line" "$makefile_path"
        sed -i '/wget/d' "$makefile_path"
    else
        echo "Warning: lucky Makefile 中未找到 'Build/Prepare'。跳过。" >&2
    fi
}

clone_adguardhome() {
    clone_packages "luci-app-adguardhome" \
        "${GITHUB_BASE}wzdddyy/luci-app-adguardhome.git" \
        "$OPENWRT_PACKAGES_DIR/luci-app-adguardhome"
}

clone_easytier() {
    local EASYTIER_DIR="$OPENWRT_PACKAGES_DIR/luci-app-easytier"
    local TEMP_DIR="$OPENWRT_PACKAGES_DIR/easytier-temp"

    (cd "$BUILD_DIR" && ./scripts/feeds install -f luci-lib-jsonc)

    clone_packages "luci-app-easytier" \
        "${GITHUB_BASE}EasyTier/luci-app-easytier.git" \
        "$TEMP_DIR" \
        "luci-app-easytier" \
        "" \
        "" \
        "$TEMP_DIR/luci-app-easytier" \
        "$EASYTIER_DIR"

    rm -rf "$TEMP_DIR"
}

clone_oaf() {
    local OAF_REPO="${GITHUB_BASE}destan19/OpenAppFilter.git"
    local OAF_DIR="$OPENWRT_PACKAGES_DIR/OpenAppFilter"
    local TEMP_DIR="$OPENWRT_PACKAGES_DIR/oaf-temp"

    (cd "$BUILD_DIR" && ./scripts/feeds install -f kmod-ipt-conntrack kmod-ipt-nat)
    
    clone_packages "OpenAppFilter" \
        "$OAF_REPO" \
        "$TEMP_DIR" \
        "oaf open-app-filter luci-app-oaf" \
        "" \
        "mkdir -p \"$OAF_DIR\" && rm -rf \"$OAF_DIR/oaf\" \"$OAF_DIR/open-app-filter\" \"$OAF_DIR/luci-app-oaf\" && mv \"$TEMP_DIR/oaf\" \"$TEMP_DIR/open-app-filter\" \"$TEMP_DIR/luci-app-oaf\" \"$OAF_DIR/\""

    rm -rf "$TEMP_DIR"

    local oaf_makefile="$OAF_DIR/oaf/Makefile"
    if [ -f "$oaf_makefile" ] ; then
        sed -i 's/DEPENDS:=.*oaf/DEPENDS:=+kmod-ipt-conntrack +kmod-ipt-nat/g' "$oaf_makefile"
    fi

    local appfilter_config="$OAF_DIR/open-app-filter/files/etc/config/appfilter"
    if [ -f "$appfilter_config" ] ; then
        sed -i "s/option enabled '1'/option enabled '0'/g" "$appfilter_config"
    fi

    local disable_script="$OAF_DIR/luci-app-oaf/root/etc/uci-defaults/99_disable_oaf"
    mkdir -p "$(dirname "$disable_script")"
    cat > "$disable_script" << 'EOF'
#!/bin/sh
[ "$(uci get appfilter.global.enable 2>/dev/null)" = "0" ] && {
    /etc/init.d/appfilter disable
    /etc/init.d/appfilter stop
}
EOF
    chmod +x "$disable_script"
}

clone_diskman() {
    local path="$OPENWRT_PACKAGES_DIR/luci-app-diskman"
    local repo_url="${GITHUB_BASE}lisaac/luci-app-diskman.git"
    local temp_dir="$OPENWRT_PACKAGES_DIR/diskman"
    
    clone_packages "luci-app-diskman" \
        "$repo_url" \
        "$temp_dir" \
        "applications/luci-app-diskman" \
        "" \
        "" \
        "$temp_dir/applications/luci-app-diskman" \
        "$path"
    
    sed -i 's/fs-ntfs /fs-ntfs3 /g' "$path/Makefile"
    sed -i '/ntfs-3g-utils /d' "$path/Makefile"
}

_sync_luci_lib_docker() {
    local repo_url="${GITHUB_BASE}lisaac/luci-lib-docker.git"
    local luci_lib_docker_dir="$OPENWRT_PACKAGES_DIR/luci-lib-docker"
    
    mkdir -p "$OPENWRT_PACKAGES_DIR" || return
    
    rm -rf "$luci_lib_docker_dir" 2>/dev/null || true
    if ! git clone --depth=1 "$repo_url" "$luci_lib_docker_dir"; then
        echo "错误：从 $repo_url 克隆 luci-lib-docker 仓库失败" >&2
        exit 1
    fi
    
    echo "✓ luci-lib-docker 克隆完成"
}

clone_dockerman() {
    local path="$OPENWRT_PACKAGES_DIR/luci-app-dockerman"
    local repo_url="${GITHUB_BASE}wzdddyy/luci-app-dockerman.git"
    local temp_dir="$OPENWRT_PACKAGES_DIR/dockerman"
    
    _sync_luci_lib_docker || return
    
    clone_packages "luci-app-dockerman" \
        "$repo_url" \
        "$temp_dir" \
        "applications/luci-app-dockerman" \
        "" \
        "" \
        "$temp_dir/applications/luci-app-dockerman" \
        "$path"
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
