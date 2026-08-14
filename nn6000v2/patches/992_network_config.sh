#!/bin/sh
# ============================================================
# 网络初始化配置脚本（仅 PPPoE，无 WiFi 版本）
# 首次启动时自动配置 PPPoE 宽带
# ============================================================

# ==================== PPPoE 宽带配置 ====================
# 填写你的宽带账号密码，使用 "-" 表示跳过配置
# 在 GitHub Actions 构建时可以通过输入参数自动替换此处的值
PPPOE_USERNAME="-"
PPPOE_PASSWORD="-"
# ============================================================

board_name=$(cat /tmp/sysinfo/board_name 2>/dev/null)

setup_pppoe() {
	if [ "$PPPOE_USERNAME" = "-" ] || [ "$PPPOE_PASSWORD" = "-" ]; then
		echo "PPPoE: 使用占位符，跳过配置"
		return 0
	fi

	if [ ! -f /etc/config/network ]; then
		echo "PPPoE: network 配置文件不存在"
		return 1
	fi

	local wan_proto=$(uci -q get network.wan.proto)
	local wan_username=$(uci -q get network.wan.username)
	local wan_password=$(uci -q get network.wan.password)

	if [ "$wan_proto" = "pppoe" ] && [ "$wan_username" != "-" ] && [ "$wan_password" != "-" ]; then
		echo "PPPoE: 已配置有效账号，跳过"
		return 0
	fi

	uci -q batch <<EOF
set network.wan.proto='pppoe'
set network.wan.username='${PPPOE_USERNAME}'
set network.wan.password='${PPPOE_PASSWORD}'
set network.wan.keepalive='5 3'
set network.wan.demand='0'
EOF

	uci commit network
	echo "PPPoE: 配置完成 - 用户名: ${PPPOE_USERNAME}"
}

setup_pppoe