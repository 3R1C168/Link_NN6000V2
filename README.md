***

## 1. 项目信息

- **参考脚本**：<https://github.com/ZqinKing/wrt_release.git>
- **源码来源**：<https://github.com/VIKINGYFY/immortalwrt.git> - main
- **上游锁定**：构建不追 HEAD，而是使用金丝雀验证过的提交（`nn6000v2/UPSTREAM_COMMIT`），上游更新先试编、验证通过才跟进
- **设备支持**：Link\_NN6000V2，内核分区 12m，**仅无 WiFi 版本**（不含 ath11k 驱动，日常走有线 / 外接 AP）
- **固件发布**：每三天发布一次，包含最新已验证源码和插件。[点击下载](https://github.com/3R1C168/Link_NN6000V2/releases/latest)

***

## 2. 构建策略

| 工作流 | 说明 |
| ------------ | ----------- |
| **Canary_Check** | 每 3 天（正式构建前 4 小时）拉上游最新提交试编；成功则更新 `UPSTREAM_COMMIT` 锁，失败则不动锁 |
| **Go_Release** | 每 3 天（UTC 20:00）使用锁定的上游提交正式构建；也可手动触发（`workflow_dispatch` 可填 PPPoE 账号密码） |

> 说明：snapshot 固件与官方 release 软件源不兼容（官方 snapshot 已切换 apk 格式），固件内已禁用 opkg 外部源。需要加插件请改配置重新编译，不要在设备上 opkg 安装。

***

## 3. 固件配置

### 3.1 系统配置

| 配置项          | 默认值         | 说明                                       |
| ------------ | ----------- | ---------------------------------------- |
| **LAN IP**   | `10.0.0.1`  | (nn6000v2/scripts/update.sh) |
| **Web 密码**  | `无`  | root 无密码，首次启动自行设置 |
| **PPPoE 账号** | **未配置**     | (nn6000v2/patches/992_network_config.sh)，手动触发构建时可传入 |

***

### 3.2 预装插件（12 个）

| 插件名称                     | 功能说明          |
| ------------------------ | ------------- |
| **luci-theme-argon** + **luci-app-argon-config** | Argon 主题及配置 |
| **luci-app-quickfile**   | 文件管理（nginx 后端）         |
| **luci-app-ttyd**        | Web 终端          |
| **luci-app-upnp**        | UPnP 端口映射     |
| **luci-app-adguardhome** | 广告过滤（DNS）          |
| **luci-app-autoreboot**  | 定时重启          |
| **luci-app-tailscale-community** | Tailscale 虚拟组网 |
| **luci-app-openclash**   | OpenClash（Clash 图形界面，mihomo 内核） |
| **luci-app-nikki**       | Nikki（mihomo 现代前端，与 OpenClash 二选一启用） |
| **luci-app-mosdns**      | MosDNS DNS 分流（v2ray-geodata 提供 geo 数据） |

> OpenClash 与 Nikki 同为 mihomo 内核前端，日常建议只用一个（同时运行会抢占端口 / 防火墙规则）。

***

## 4. 插件来源

- 基础 feeds：<https://github.com/immortalwrt/luci>、<https://github.com/immortalwrt/packages>
- OpenClash：<https://github.com/vernesong/OpenClash>
- Nikki：<https://github.com/nikkinikki-org/OpenWrt-nikki>
- MosDNS：<https://github.com/sbwml/luci-app-mosdns> + <https://github.com/sbwml/v2ray-geodata>
- 其余（quickfile / adguardhome / tailscale 等）：<https://github.com/kenzok8/openwrt-packages>

***

## 5. 项目结构

```
Link_NN6000V2/
├── .github/workflows/
│   ├── canary.yml        # 金丝雀构建（上游验证 + 更新提交锁）
│   └── release.yml       # 正式固件构建与发布
└── nn6000v2/              # 设备专用目录
    ├── UPSTREAM_COMMIT    # 锁定的上游源码提交号
    ├── configs/           # 固件配置文件目录
    ├── patches/           # 设备补丁目录
    │   ├── cpuusage       # CPU 使用率补丁
    │   ├── smp_affinity   # SMP 中断平衡补丁
    │   ├── nss_diag.sh    # NSS 诊断脚本
    │   └── tempinfo       # 温度信息补丁
    └── scripts/           # 编译脚本目录
        ├── build.sh       # 编译脚本（单一无 WiFi 版本）
        ├── feeds.sh       # feeds 配置脚本
        ├── general.sh     # 通用设置脚本
        ├── packages.sh    # 包管理脚本（插件 clone 与白名单 install）
        ├── system.sh      # 系统配置脚本
        └── update.sh      # 更新脚本（含 gettext-full 版本钉住）
```

***

## ImmortalWrt

<div align="center">

![ImmortalWrt](immortalwrt.png)

</div>

***
