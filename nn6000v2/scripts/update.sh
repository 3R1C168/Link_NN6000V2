#!/usr/bin/env bash
set -e
set -o errexit
set -o errtrace

error_handler() {
    echo "Error occurred in script at line: ${BASH_LINENO[0]}, command: '${BASH_COMMAND}'"
}

trap 'error_handler' ERR

REPO_URL=$1
REPO_BRANCH=$2
BUILD_DIR=$3
COMMIT_HASH=$4

# Convert BUILD_DIR to absolute path
if [[ "$BUILD_DIR" != /* ]]; then
    BUILD_DIR="$(pwd)/$BUILD_DIR"
fi

FEEDS_CONF="feeds.conf.default"
GOLANG_REPO="https://github.com/sbwml/packages_lang_golang"
GOLANG_BRANCH="26.x"
THEME_SET="argon"
LAN_ADDR="10.0.0.1"

SCRIPT_DIR=$(cd $(dirname $0) && pwd)
BASE_PATH=${BASE_PATH:-$(dirname "$SCRIPT_DIR")}

source "$SCRIPT_DIR/general.sh"
source "$SCRIPT_DIR/feeds.sh"
source "$SCRIPT_DIR/packages.sh"
source "$SCRIPT_DIR/system.sh"


main() {
    clone_repo
    clean_up
    reset_feeds_conf
    update_feeds
    update_golang
    clone_quickfile
    clone_adguardhome
    clone_luci_tailscale
    # 自定义新增的三个插件源（OpenClash / Nikki / MosDNS）
    clone_openclash
    clone_nikki
    clone_mosdns
    install_feeds
    remove_tweaked_packages
    change_dnsmasq2full
    fix_default_set
    fix_mk_def_depends
    update_default_lan_addr
    update_affinity_script
    update_dnsmasq_conf
    change_cpuusage
    set_custom_task
    update_nss_pbuf_performance
    update_nss_diag
    fix_compile_coremark
    set_build_signature
    add_backup_info_to_sysupgrade
    remove_attendedsysupgrade
    fix_rust_compile_error
    fix_kconfig_recursive_dependency
    set_nginx_default_config
    update_nginx_ubus_module
    fix_nginx_configure
    update_uwsgi_limit_as
    update_script_priority
    fix_openssl_ktls
    fix_opkg_check
    fix_quectel_cm
    fix_quickstart
    revert_gettext_full
}

# 上游 gettext-full 1.0 host 编译损坏（stdcountof.h 缺失），
# 用官方 openwrt 的 0.24.2 覆盖。必须在 reset_feeds_conf 之后执行，
# 否则会被 git reset --hard 回滚。上游修复后可删除本函数及调用。
revert_gettext_full() {
    local dst="$BUILD_DIR/package/libs/gettext-full"
    if grep -q "PKG_VERSION:=0.24.2" "$dst/Makefile" 2>/dev/null; then
        echo "gettext-full 已是 0.24.2，跳过覆盖"
        return 0
    fi
    local tmp
    tmp=$(mktemp -d)
    git clone --depth 1 --filter=blob:none --sparse https://github.com/openwrt/openwrt.git "$tmp/ow" || {
        echo "错误：克隆官方 openwrt 失败" >&2; rm -rf "$tmp"; exit 1;
    }
    (cd "$tmp/ow" && git sparse-checkout set package/libs/gettext-full)
    rm -rf "$dst"
    cp -r "$tmp/ow/package/libs/gettext-full" "$dst"
    rm -rf "$tmp"
    grep "PKG_VERSION" "$dst/Makefile"
}

main "$@"
