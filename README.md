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
4. 本人不会编程，本次修改由 AI 完成，仅为个人使用。

---

## ✨ 本维护分支新增/修复的内容

### 1. 修复 qBittorrent 端口修改失败（兼容 qBittorrent 5.2.x）

原版 `qbittorrent.sh` 在 qBittorrent 4.3+ / 5.x 上无法修改监听端口，本分支已修复：

- **兼容 qBittorrent 5.2.x 的登录 API 破坏性变更**：
  - 会话 cookie 由 `SID` 改名为 `QBT_SID_<WebUI端口>`（如 `QBT_SID_8085`）
  - 登录成功响应码由 `200` 改为 `204`
  - 原脚本按 `SID=` 正则抓取 cookie 必然失败 → 改为 **curl cookie jar（`-c`/`-b`）**，完全不依赖 cookie 名称，对 4.x / 5.0 / 5.1 / 5.2.x 全兼容
- **通过 CSRF / Host header 校验**：登录与 `setPreferences` 请求均携带与 Host 同源的 `Referer` / `Origin`，避免 qBittorrent 4.3+ 默认开启 CSRF 保护后返回 401
- **密码安全传输**：改用 `--data-urlencode` 编码，修复密码含 `&`、`^` 等特殊字符时被截断导致的登录失败
- 重试逻辑完善、缺失参数时给出明确错误提示

> 注：若通过域名访问 qBittorrent WebUI，请在 qBittorrent「Web UI 域名白名单」中加入该域名，否则 Host header 校验同样会 401。

### 2. 新增：打洞端口同步到防火墙规则（自定义脚本）

新增 `firewall_nas.sh`，在 natmap 打洞成功后自动把获取到的外部端口写入防火墙规则：

- 默认目标规则：`nas_incoming_5`（放行 qBittorrent 的 IPv6 入站端口，目标规则需先自行创建）
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

### 4. 修复防火墙 IPv6 放行与 Cloudflare 联动问题（2026-08）

#### 4.1 修复 `firewall-forward.sh` IPv6 放行条件失效

原 IPv6 放行判断存在语法错误（`[ [ ... ] && [ ... ] ]` 嵌套、`["...` 缺少空格），该分支**永远不会执行**；且 qbittorrent 的 IPv6 开关判断写反。已修正为：

```bash
if { [ "${LINK_MODE}" = transmission ] && [ "${LINK_TR_ALLOW_IPV6}" = 1 ]; } || \
   { [ "${LINK_MODE}" = qbittorrent ] && [ "${LINK_QB_ALLOW_IPV6}" = 1 ]; }; then
```

#### 4.2 修复 `cloudflare_ddns.sh` 双等号赋值 bug

`local local_result==$(curl ...)` 多写了一个 `=`，导致变量值变成 `=响应体`，jq 解析失败、DDNS 更新**永远失败**。已去掉多余等号。

#### 4.3 修复 init 脚本重复 `-i` 参数

`forward_firewall_target_interface` 被误追加为 natmap 的 `-i` 参数，与 `general_wan_interface` 同时配置时**覆盖 WAN 接口，导致 natmap 绑定到错误接口、打洞失效**。该接口仅需通过环境变量传给转发插件，已删除多余的 `-i` 追加。

#### 4.4 修复 `cloudflare_redirect_rule.sh` 更新失败（动态规则字段不匹配）

**现象**：日志反复出现 `cloudflare_redirect_rule 达到最大重试次数，无法修改`。

**原因**：Cloudflare 控制台创建的动态跳转规则，目标 URL 存于 `target_url.expression`；旧脚本写入 `target_url.value`，两个字段并存被 API 拒绝（`400 错误码 20083: target_url should be either value or expression`）。

**修复**：脚本统一将 `target_url` 整体替换为 `{"value": "<URL>"}`（静态跳转形式，纯 URL 即可被 API 接受），自动兼容动态/静态规则；失败时把 Cloudflare 返回的具体 errors 写入 `/var/log/natmap/natmap.log`。`cloudflare_origin_rule.sh` 同步改进。

#### 4.5 全局健壮性

- 所有插件脚本的 curl 统一增加超时（API 类 `-m 20`、通知类 `-m 15`），避免网络卡死导致脚本挂起、进程堆积
- `update.sh` 增加 `flock` 并发锁：natmap 异步执行回调且不等待返回，多实例/连续触发时串行化，避免并发写 uci/防火墙冲突
- 修正 LuCI 帮助文案：`NEW_PORT` 应替换 URL 中的**端口**（冒号后的数字），示例 `http://1.2.3.4:NEW_PORT/`（此前示例为路径形式，易误导）

### 5. 脚本健壮性批量修复（2026-09）

#### 5.1 服务与主脚本

| 文件 | 问题与修复 |
|---|---|
| `init.d/natmap` | `procd_append_param env` 未加引号：配置值含空格（如自定义脚本路径、Gotify URL）时会被拆成两个参数，环境变量损坏。已整体加引号 |
| `update.sh` | ① 移除 busybox ash 不支持的 bashism `export -n`（OpenWrt 上每次执行自定义脚本分支都会报错）；② 提前 `mkdir -p /var/run/natmap` 与日志目录，修复锁等待超时分支、独立运行时写状态 JSON/日志失败 |
| 默认配置 | 默认 STUN 服务器由 `stunserver.stunprotocol.org`（项目已停止服务）改为 `stun.cloudflare.com`（仅影响新安装） |

#### 5.2 转发 / 联动插件

| 文件 | 问题与修复 |
|---|---|
| `plugin-forward/firewall-forward.sh` | IPv6 放行规则 `dest_port` 误用 IPv4 DNAT 的目标端口 `forward_target_port`。IPv6 无 NAT，qB/TR 实际监听的是打洞得到的外部端口，两者不一致时放行的是无人监听的端口、IPv6 入站全部被拒。已改为 `$outter_port` |
| `plugin-link/emby.sh` | HTTP 状态码判断修复：旧写法把响应体和状态码拼接后再 `-eq 200` 比较，Emby 返回 `204 No Content` 时被误判失败导致无限重试。改为 `-o /dev/null -w "%{http_code}"` 并接受 2xx；未加引号的变量已加引号 |
| `plugin-link/transmission.sh` | 凭据未加引号：用户名/密码含空格或特殊字符时登录失败。已改为 `-u "$USER:$PASS"` 整体传递；移除重试路径上多余的 `sleep` |
| `plugin-link/cloudflare_ddns.sh` | DNS 记录不存在时不再向空 id 的 URL（`.../dns_records/`）发起无效 PUT，日志明确提示「请先在 Cloudflare 添加该记录」，AAAA/HTTPS/SRV 三条分支均已覆盖 |

#### 5.3 通知插件（4 个）

| 文件 | 问题与修复 |
|---|---|
| `telegram_bot.sh` / `pushplus.sh` | 手工拼接 JSON：消息含引号/换行即破坏请求体。改用 `jq -n --arg` 构建；同时从「只看 curl 退出码」改为检查 HTTP 状态码——旧逻辑在 4xx/5xx 时也会误报「发送成功」且不再重试 |
| `serverchan.sh` | 手工拼 `title=x&desp=x`：消息含 `&`、`=` 或换行时参数被截断。改用 `--data-urlencode` |
| `gotify.sh` | 同上改为检查 HTTP 状态码（curl 退出码为 0 不代表服务端接受） |

---

## 📦 功能总览（继承自原版）

### 第三方服务联动（打洞成功后自动调用）

- **qBittorrent**：自动修改监听端口（已修复 5.2.x 兼容）
- **Transmission**：自动修改监听端口
- **Emby**：自动更新公网访问端口 / 连接地址
- **Cloudflare**：Origin Rules / Redirect Rules / DDNS（AAAA、HTTPS、SRV 记录）

### 消息通知

- Telegram Bot / PushPlus / Server酱 / Gotify

### 端口转发

- natmap 转发 / OpenWrt firewall DNAT 转发 / iKuai 端口映射

### 自定义脚本

- 打洞成功后执行自定义脚本（本分支的防火墙端口同步功能即基于此实现）

---

## 🚀 编译与安装

### 1. 添加软件源

在 OpenWrt 源码的 `feeds.conf.default` **首行**添加（`zzz` 前缀保证排序靠后覆盖，以覆盖官方内置 `luci-app-natmap`）：

```text
src-git zzz https://github.com/hahaher123/openwrt-natmap.git
```

### 2. 编译

```sh
./scripts/feeds update -a
./scripts/feeds install -a
make menuconfig    # 勾选 Network → natmap / luci-app-natmap
make -j$(nproc)
```

> 建议编译固件时一并集成，而非事后安装插件。

### 3. 依赖

`luci-app-natmap` 依赖：`+natmap +jq +curl +openssl-util +bash`

---

## ⚙️ 配置说明

### 基本（LuCI → 服务 → NATMap）

| 配置项 | 说明 |
|---|---|
| `general_wan_interface` | WAN 接口名（如 `wan`） |
| `general_nat_protocol` | `tcp` / `udp` |
| `general_ip_address_family` | `ipv4` / `ipv6`（留空为双栈） |
| `general_interval` | keepalive 间隔（秒） |
| `general_stun_server` | STUN 服务器（默认 `stun.cloudflare.com`） |
| `general_http_server` | HTTP 打洞服务器（TCP 模式使用） |
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

脚本默认写入防火墙规则 `nas_incoming_5` 的 `dest_port`（目标 IPv6 为空，即放行整个局域网的目标端口）。如需调整，编辑 `/usr/share/natmap/plugin-link/firewall_nas.sh` 顶部的 `RULE_NAME` / `RULE_DEST_IP` / `SYNC_PROTO` 变量。

### Cloudflare Redirect Rules 联动（本分支修复）

入口域名需在 Cloudflare 开启代理（橙云）；跳转目标域名需为 DNS-only（灰云，解析到家宽公网 IP），否则 Cloudflare 无法代理非 80/443 端口。

| 配置项 | 说明 |
|---|---|
| `link_enable` | 开启联动 `1` |
| `link_mode` | `cloudflare_redirect_rule` |
| `link_cloudflare_redirect_rule_name` | 与控制台创建的规则名（description）一致 |
| `link_cloudflare_redirect_rule_target_url` | 跳转目标 URL，**端口位置**用 `NEW_PORT` 占位，如 `http://你的ddns域名:NEW_PORT/` |

跳转链路：`https://入口域名`（橙云）→ 302 → `http://ddns域名:打洞端口`（灰云直连）→ 路由器 DNAT → 内网服务。

---

## 📁 目录结构

```text
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
│           ├── plugin-forward/                              # 转发插件
│           ├── plugin-link/
│           │   ├── qbittorrent.sh                           # 【已修复 5.2.x 兼容】
│           │   ├── transmission.sh / emby.sh / cloudflare_*.sh
│           │   └── firewall_nas.sh                          # 【新增】防火墙端口同步
│           └── plugin-notify/                               # 通知插件（均已加固）
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
| Cloudflare 联动一直重试失败 | 确认规则名与 `link_cloudflare_redirect_rule_name` 一致；看日志 `修改失败: [...]` 中 Cloudflare 返回的具体 errors（新版脚本已输出）；规则需先在控制台创建 |
| Cloudflare DDNS 提示「未找到记录」 | 需先在 Cloudflare 控制台手动创建对应类型（AAAA/HTTPS/SRV 及 SRV 目标域名的 A 记录）的 DNS 记录，脚本只更新不创建 |
| IPv6 能连接但下载器无响应 | 确认对应下载器的「允许 IPv6」已开启，且 `link_qb_ipv6_address` / `link_tr_ipv6_address` 填写了下载器的 IPv6 地址 |

---

## 📄 许可与致谢

- 本仓库继承原版许可：**Apache-2.0**（luci-app-natmap）与 **MIT**（natmap 核心）。
- 上游引用：
  1. [uvswifft/openwrt-natmap](https://github.com/uvswifft/openwrt-natmap)（原作者，已归档）
  2. [EkkoG/luci-app-natmap](https://github.com/EkkoG/luci-app-natmap)
  3. [EkkoG/openwrt-natmap](https://github.com/EkkoG/openwrt-natmap)
  4. [heiher/natmap](https://github.com/heiher/natmap)（natmap 核心程序）
