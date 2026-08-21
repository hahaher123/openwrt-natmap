下面是一份完整的 README.md，直接复制保存到你仓库根目录即可。里面用 `你的GitHub用户名` 占位，发布前替换成你自己的。

---

```markdown
# luci-app-natmap（维护分支）

> 本仓库是 [uvswifft/openwrt-natmap](https://github.com/uvswifft/openwrt-natmap)（原作者，**已归档**）的维护分支。
> 在完全继承原作者设计、功能与 Apache-2.0 许可的前提下，针对新版 OpenWrt 与新版
> qBittorrent 做了一系列适配与新增功能。**感谢原作者** [uvswifft](https://github.com/uvswifft) 
> 及上游 [EkkoG/luci-app-natmap](https://github.com/EkkoG/luci-app-natmap)、
> [heiher/natmap](https://github.com/heiher/natmap) 的工作。

---

## ⚠️ 重要提示

1. **上游已归档**：原仓库 `uvswifft/openwrt-natmap` 已归档、停止维护。本仓库在其基础上继续适配，不保证与上游同步。
2. **打洞依赖网络条件**：作者弃坑的原因是大环境运营商大搞 NAT4、打洞基本失效。本插件**仅在公网 IP / NAT1（Full Cone）环境下有效**，请先确认你的宽带类型再使用。
3. **面向 OpenWrt 23.0+ / luci2 / golang>=1.20**：自 OpenWrt 23.0 之后使用 luci2 与新版 golang，旧版插件不兼容。本分支以 **OpenWrt 25.12.4** 为基准测试。
4. 本人不会编程，本次修改由AI完成，仅为个人使用。

---

## ✨ 本维护分支新增/修复的内容

### 1. 修复 qBittorrent 端口修改失败（兼容 qBittorrent 5.2.x）

原版 `qbittorrent.sh` 在 qBittorrent 4.3+ / 5.x 上无法修改监听端口，本分支已修复：

- **兼容 qBittorrent 5.2.x 的登录 API 破坏性变更**：
  - 会话 cookie 由 `SID` 改名为 `QBT_SID_<WebUI端口>`（如 `QBT_SID_8085`）
  - 登录成功响应码由 `200` 改为 `204`
  - 原脚本按 `SID=` 正则抓取 cookie 必然失败 → 改为 **curl cookie jar（-c/-b）**，完全不依赖 cookie 名称，对 4.x / 5.0 / 5.1 / 5.2.x 全兼容
- **通过 CSRF / Host header 校验**：登录与 `setPreferences` 请求均携带与 Host 同源的 `Referer` / `Origin`，避免 qBittorrent 4.3+ 默认开启 CSRF 保护后返回 401
- **密码安全传输**：改用 `--data-urlencode` 编码，修复密码含 `&`、`^` 等特殊字符时被截断导致的登录失败
- 重试逻辑完善、缺失参数时给出明确错误提示

> 注：若通过域名访问 qBittorrent WebUI，请在 qBittorrent「Web UI 域名白名单」中加入该域名，否则 Host header 校验同样会 401。

### 2. 新增：打洞端口同步到防火墙规则（自定义脚本）

新增 `firewall_nas.sh`，在 natmap 打洞成功后自动把获取到的外部端口写入防火墙规则：

- 默认目标规则：`nas_incoming_5`（放行qBittorrent的 IPv6入站端口，目标规则需先自行创建）
- 自动执行 `uci set ... dest_port` 并 `/etc/init.d/firewall reload`
- 端口/协议未变化时跳过 reload，避免频繁重启防火墙
- 支持 tcp/udp 协议自动合并；兼容「命名 section」与「option name」两种规则写法
- 通过 LuCI「自定义脚本」或 plugin-link 方式接入

### 3. 升级 natmap 核心至 20260214

内置 natmap 程序由 20240813 升级到官方最新 **20260214**（OpenWrt 25.12 官方 feed 同版本），获得以下改进：

- **端口复用**：keepalive 时尽量沿用同一端口，只有端口不可用时才更换，减少端口跳变
- 连接失败自动重试（最多 100 次）+ 修复多处 fd 泄漏
- 转发空闲超时默认值 120s → 300s
- 新增 `-c`（UDP STUN 探测周期）、`-C`（TCP 拥塞控制）、`-b ~`（端口区间随机分配）等参数
- 命令行接口向后兼容，原有启动参数全部保留

---

## 📦 功能总览（继承自原版）

### 第三方服务调用（打洞成功后自动联动）
- **qBittorrent**：自动修改监听端口（已修复 5.2.x 兼容）
- **Transmission**：自动修改监听端口
- **Emby**：配合 Emby Connect 更新连接地址
- **Cloudflare Origin Rules / Redirect Rules / DDNS**

### 通知
- Telegram Bot / PushPlus / Server酱 / Gotify

### 端口转发
- natmap 转发 / OpenWrt firewall dnat 转发 / ikuai 端口映射

### 自定义脚本
- 打洞成功后执行自定义脚本（本分支的防火墙同步功能即基于此实现）

---

## 🚀 使用（编译）

### 添加软件源

在 OpenWrt 源码的 `feeds.conf.default` **首行**添加，以覆盖官方内置 `luci-app-natmap`：

```
src-git zzz https://github.com/hahaer123/openwrt-natmap.git
```

### 编译

./scripts/feeds update -a
./scripts/feeds install -a
make menuconfig   # 勾选 Network → natmap / luci-app-natmap
make -j$(nproc)
```

> 建议编译固件时一并集成，而非事后安装插件。

### 依赖

`luci-app-natmap` 依赖：`+natmap +jq +curl +openssl-util +bash`

---

## ⚙️ 配置说明

### 基本（LuCI → 服务 → NATMap）

| 配置项 | 说明 |
|---|---|
| `general_wan_interface` | WAN 接口名（如 `wan`） |
| `general_nat_protocol` | `tcp` / `udp` |
| `general_ip_address_family` | `ipv4` / `ipv6` |
| `general_interval` | keepalive 间隔（秒） |
| `general_stun_server` | STUN 服务器 |
| `general_http_server` | HTTP 打洞服务器 |
| `general_bind_port` | 绑定端口（单端口或范围） |

### qBittorrent 联动

| 配置项 | 说明 |
|---|---|
| `link_enable` | 开启联动 `1` |
| `link_mode` | `qbittorrent` |
| `link_qb_web_url` | qB WebUI 地址 |
| `link_qb_username` / `link_qb_password` | qB 登录凭据 |
| `link_advanced_max_retries` / `link_advanced_sleep_time` | 重试次数与间隔 |

### 防火墙端口同步（本分支新增）

开启「自定义脚本」并指向本仓库内置脚本：

```sh
uci set natmap.@natmap[0].custom_script_enable=1
uci set natmap.@natmap[0].custom_script_path=/usr/share/natmap/plugin-link/firewall_nas.sh
uci commit natmap
/etc/init.d/natmap restart
```

脚本默认写入防火墙规则 `nas_incoming_5` 的 `dest_port`（目标 IPv6 为 空，即放行整个局域网的目标端口）。如需调整，编辑 `/usr/share/natmap/firewall_nas.sh` 顶部的 `RULE_NAME` / `RULE_DEST_IP` / `SYNC_PROTO` 变量。

---

## 📁 目录结构

```
├── luci-app-natmap/
│   ├── Makefile
│   ├── htdocs/luci-static/resources/view/natmap/natmap.js   # LuCI2 前端
│   ├── po/                                                   # 多语言
│   └── root/
│       ├── etc/config/natmap                                # 默认配置模板
│       ├── etc/init.d/natmap                                # procd 服务
│       └── usr/share/natmap/
│           ├── update.sh                                    # 打洞成功回调入口
│           ├── link.sh / forward.sh / notify.sh
│           ├── plugin-link/
│           │   ├── qbittorrent.sh                           # 【已修复 5.2.x 兼容】
│           │   ├── transmission.sh / emby.sh / cloudflare_*.sh
│           ├── firewall_nas.sh                              # 【新增】防火墙端口同步
│           └── plugin-notify/ ...
└── natmap/
    └── Makefile                                              # 【已升级】natmap 20260214
```

---

## 🛠 常见问题

| 问题 | 排查 |
|---|---|
| 打洞失败 / 一直重试 | 确认宽带是公网 IP / NAT1；更换 STUN 服务器测试 |
| qB 端口改不动 | 确认 `link_qb_web_url` 与 qB 实际地址一致；域名访问需加入 qB 域名白名单；日志看 `/var/log/natmap/natmap.log` |
| 防火墙规则未更新 | 确认 `custom_script_enable=1` 且脚本路径存在（`file` 校验要求文件真实存在） |
| 服务起不来 `validation failed` | `custom_script_path` 指向的文件必须存在 |

---

## 📄 许可与致谢

- 本仓库继承原版许可：**Apache-2.0**（luci-app-natmap）与 **MIT**（natmap 核心）。
- 上游引用：
  1. [uvswifft/openwrt-natmap](https://github.com/uvswifft/openwrt-natmap)（原作者，已归档）
  2. [EkkoG/luci-app-natmap](https://github.com/EkkoG/luci-app-natmap)
  3. [EkkoG/openwrt-natmap](https://github.com/EkkoG/openwrt-natmap)
  4. [heiher/natmap](https://github.com/heiher/natmap)（natmap 核心程序）

