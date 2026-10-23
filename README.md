# SKYBYTE Xray Manager

[English](README_EN.md) · [YouTube](https://www.youtube.com/@SKYBYTE9119)

如果这个脚本对你有帮助，欢迎[订阅我的 YouTube 频道 SKYBYTE](https://www.youtube.com/@SKYBYTE9119)，支持后续维护与更新！

<!-- SKYBYTE_AFFILIATE_HEADER_START -->
## VPS 服务商推广链接

### 1. 住宅 / ISP IP：跨境电商、TikTok 网络环境

**[丽萨主机（LisaHost）](https://lisahost.com/aff.php?aff=11072)**：可关注住宅 / ISP IP 套餐，按应用需求评估跨境电商、TikTok 和海外账号运营所需的网络环境。IP 类型和可用地区以具体套餐为准。

### 2. 精品线路 VPS：主力自用 / 朋友分享 / 中转前置

**[DMIT](https://www.dmit.io/aff.php?aff=18635)**：提供包括 CN2 GIA 在内的中国大陆优化线路方案，可按预算和实际线路测试选择日常节点或入口服务器。

**[搬瓦工（BandwagonHost）](https://bandwagonhost.com/aff.php?aff=83101)**：可关注 CN2 GIA 等线路套餐，适合比较日常自用和入口服务器的线路选择。

### 3. 入门 VPS：新手练手 / 备用节点

**[RackNerd](https://my.racknerd.com/aff.php?aff=18647)**：可关注低预算 VPS 和年付优惠，用于练习 Ubuntu/Debian、部署 Xray 和搭建备用节点。

其他选择：**[AkileCloud](https://akile.ai/register?aff_code=0be67084-ae2e-4095-a586-2a3ee5c970f0)**。

**推广说明：** 通过以上链接购买，可能为作者带来佣金，用于支持 SKYBYTE 项目的开发与维护。价格、线路、带宽和 IP 类型以商家具体套餐为准；实际速度及平台可用性需要结合自己的网络测试。
<!-- SKYBYTE_AFFILIATE_HEADER_END -->

---

独立的 Bash VPS 管理工具，使用官方 Xray-core，支持 Ubuntu/Debian、中文和英文界面。版本 **0.1.14**，默认核心 **v26.3.27**。本项目与 SKYBYTE Manager 的 sing-box 配置、二进制和服务使用不同路径，可在端口不冲突时共存。

## 启动概览

进入主菜单即显示操作系统、架构、内核、CPU、内存/Swap、根分区用量、运行时间与负载；同时显示 Xray 服务运行/失败/停止状态、开机自启、实际核心版本、已安装协议与 TCP 端口、当前 BBR 算法及 WARP 分流状态。组件列表检测官方 WARP 客户端、UFW、firewalld、Fail2ban 和二维码工具，区分已安装、已启用、运行中及状态未知。

概览仅查询本机，单条命令最多等待 2 秒；不访问外网、不展示节点凭据、不改变配置，查询失败不会阻止打开菜单。“已配置分流”不表示 WARP 出口已连通，使用菜单 14 检测。

## WARP 分流与平台检测

入口为 **14**。可安装官方 WARP 本机代理、复用现有回环 SOCKS5 出口，或关闭本项目分流恢复直连。安装使用 [Cloudflare 官方签名软件源](https://pkg.cloudflareclient.com/)；确认条款后仅配置本机代理模式，默认 `127.0.0.1:40000`。已有客户端或残留注册数据时停止自动安装，保留其设置；与 sing-box 共用已有代理时，两项目分别管理自己的节点路由。

提供 Netflix、Disney+、ChatGPT、Gemini、四者组合与自定义域名后缀预设。Gemini 覆盖 `gemini.google.com`、`aistudio.google.com` 和 `generativelanguage.googleapis.com`，不分流整个 Google 域名。启用前检查仅回环监听、通过 SOCKS5 远程 DNS 实际请求 Cloudflare trace，并校验 `warp=on/plus`、出口 IP 和国家字段；验证失败不改节点分流。只有匹配域名的 TCP 经过 WARP，其余流量直连；匹配的 UDP 被阻断，以允许应用回退 TCP。IP 直连、ECH 或未收录域名可能无法匹配，不承诺任何平台或国家解锁。系统默认路由不切换，WARP 失效时匹配流量不会自动改用直连。

路由和节点共用已有候选配置校验、服务事务、备份和恢复机制。切换时保留 UUID、密钥、地址、端口与原先的服务启停状态；重启失败回退。恢复含 WARP 的备份后，需要本机相应代理仍可用。关闭分流及卸载管理器会保留 WARP 软件、注册、连接与软件源，也不修改 sing-box 或其他项目。

选项 **5** 对比直连 IPv4 与 WARP 的 Netflix、Disney+、ChatGPT、Gemini 匿名页面响应。显示明确地区限制、验证/拒绝、连接失败及未知；HTTP 200 和 WARP trace 通过都不代表实际播放、完整片库或账号可用。不执行第三方检测脚本，不发送登录凭据；报告只保存分类与状态，位于配置目录 `reports/`，权限 600。参考 [WARP 本机代理模式](https://developers.cloudflare.com/warp-client/warp-modes/) 与 [Xray SOCKS 出站](https://xtls.github.io/en/config/outbounds/socks.html)。

## 三种节点

| 安装方式 | 传输与安全 | 默认 TCP 端口 | 准备条件 |
| --- | --- | --- | --- |
| VLESS + Reality + Vision | RAW/TCP + Reality，Vision flow | 443 | 可达、支持 TLS 1.3 和 HTTP/2 的握手目标 |
| VLESS + XHTTP + Reality | XHTTP + Reality，不混入 Vision flow | 443 | 同上，无需自己的域名证书 |
| VLESS + XHTTP + TLS/CDN | XHTTP + TLS，默认开启验证 | 2053 | 自有域名、已有可信 fullchain 与匹配私钥 |

可依次安装三种节点，每种协议一个入口、不同 TCP 端口。TCP/Reality 与 XHTTP/Reality 默认均为 443，同时安装时需手动指定不同的空闲端口；已有节点端口保持不变。重复安装已存在的协议会拒绝；编辑节点、更新证书和核心升级保留已有 UUID 与密钥。删除后重新安装会生成新凭据。

支持 IPv4 或 IPv6 监听，以及自定义客户端连接地址、端口、节点名和 XHTTP 路径。支持客户端 `auto`、`packet-up`、`stream-up`、`stream-one` 模式，服务端接受兼容的模式；CDN 模式默认 `packet-up`，拒绝在该模式选择 `stream-one`。参考 [Xray 的 XHTTP 说明](https://github.com/XTLS/Xray-core/discussions/4113) 和 [Reality 文档](https://xtls.github.io/config/transports/reality.html)。

## 安装

需要 **root、Ubuntu/Debian 和 systemd**；二进制支持 amd64、arm64。在 VPS 的 root 终端运行下面这一条命令；缺少 `curl` 时自动安装 `curl` 和 CA 证书：

<!-- SKYBYTE_INSTALL_COMMAND_START -->
```bash
(if ! command -v curl >/dev/null; then apt-get update && apt-get install -y curl ca-certificates; fi && script=$(curl -q -fsSL --max-time 60 https://raw.githubusercontent.com/skylink9119/skybyte-xray-manager/main/bootstrap.sh) && bash -c "$script")
```
<!-- SKYBYTE_INSTALL_COMMAND_END -->

启动脚本会把安装入口下载到独立临时目录，下载或语法检查失败立即停止，结束后清理临时文件，保留菜单交互输入。缺少 `curl` 时需要可用的 APT 软件源。安装入口仍会下载同版本主脚本并核对发布文件中的 SHA256，校验失败立即停止。安装入口核对自身与主脚本版本，拒绝覆盖更高或无法识别的已安装版本；相同版本可重装。安装后，重新登录 SSH 也可以输入下面的快捷命令：

```bash
xr
```

菜单 **13：更新管理脚本** 可检查并安装最新正式版；也可重新运行安装命令更新，已有节点状态与凭据保留。`xr` 若已被其他程序占用，安装会停止并保留原文件；不会覆盖 sing-box 的 `sb` 命令。

也可以上传完整发布包，解压后进入目录执行：

```bash
bash install.sh
```

也可在完整目录直接运行 `bash xray-manager.sh`。无需 sudo。缺少 Python 或 flock 时，安装入口会询问是否安装基础依赖。APT 索引更新失败会停止，不继续使用旧索引安装。核心仅从官方稳定 Release 下载，并按 GitHub Release 的 SHA256 摘要验证。

独立仓库：[skylink9119/skybyte-xray-manager](https://github.com/skylink9119/skybyte-xray-manager)。正式发布代码位于 `main`。发布页提供安装入口、自包含主脚本、完整源码包与 `SHA256SUMS`；完整包可直接本地安装，单独下载入口时会联网获取主脚本。

首次启动选择语言。主菜单使用与 sing-box 项目相同的 SKYBYTE ASCII Logo，并显示 Xray 项目名称。菜单和提问绿色加粗，节点信息黄色，链接和错误红色，警告黄色；非终端或 `NO_COLOR=1` 可关闭颜色。操作确认统一提示 `[y/N]`，输入 `y` 或 `Y` 确认；回车或 `n/N` 取消。取消节点安装会正常返回菜单，不显示安装失败。

安装时，“客户端连接地址”必填：填写这台 VPS 的公网 IP 或指向它的域名；它与 Reality 握手域名是两项不同的设置。带方括号的选项才可回车使用默认值。脚本会先检查地址与监听端口；若提示 TCP 443 已被占用（例如已有 sing-box 或网站），请选择其他空闲端口并放行对应 TCP 规则，不要直接停止已有服务。`TLSv1.3 / h2` 只表示握手目标检查通过，节点还需完成配置与服务启动。

安装 TCP/Reality 或 XHTTP/Reality 时提供握手域名预设：Microsoft（`www.microsoft.com`，默认）、Apple（`www.apple.com`）、Amazon（`www.amazon.com`）、Cloudflare（`www.cloudflare.com`）和 Google（`dl.google.com`）。选择编号后，握手目标默认跟随为所选域名的 `:443`，仍可手动修改；也可选择自定义或直接输入域名，输入 0 返回。每次仍从 VPS 检查所选目标的 TLS 1.3、HTTP/2 和证书，检查失败不继续下载核心或写入节点配置。预设不保证所有线路可达。

## 菜单

| 选项 | 操作 |
| --- | --- |
| 1 | 安装或添加三种节点之一 |
| 2 | 查看节点链接与客户端导出文件 |
| 3 | 本地生成节点二维码 |
| 4 | 服务状态、启停、重启、配置检查与日志 |
| 5 | 重命名、删除协议、更新 TLS 证书、修改地址/端口/路径 |
| 6 | 校验并更新官方稳定 Xray 核心 |
| 7 / 8 | 配置备份与恢复 |
| 9 / 10 / 11 | 使用说明、语言、卸载 |
| 12 | 防火墙安装/停用/卸载/端口放行、BBR 状态/启用/恢复 |
| 13 | 检查并更新管理脚本 |

**5 → 4**：选择已安装协议后，可修改客户端连接地址、监听 TCP 端口及 XHTTP 路径；每项回车保留原值，全部留空直接返回。Vision 不显示路径选项。UUID、Reality 密钥、Short ID、TLS SNI、证书及其他节点保持原值。修改前校验输入、托管节点端口冲突及新端口占用，校验通过后同步生成服务端配置、节点链接、Base64 和 Xray 客户端 JSON。运行中的服务会重启，失败则回退；原先停止的服务继续停止。修改后请从菜单 2 获取新链接或配置，重新导入客户端，并放行新 TCP 端口；CDN 使用者还需确认新端口受提供商支持。

需要在系统防火墙和服务商安全组放行实际 TCP 端口。系统防火墙可通过菜单 12 操作；服务商安全组仍需自行设置。

## 更新管理脚本

菜单 **13** 检查本项目最新正式 GitHub Release，显示当前版本与可更新版本，输入 `y` 后更新已安装的 `/usr/local/lib/skybyte-xray/manager.sh`。不安装预览版，不更新到相同或更旧版本；如果从旧副本启动，也拒绝覆盖更高版本的已安装脚本。v0.1.3 及更早版本需要先运行 v0.1.14 安装命令更新一次，之后即可使用菜单 13。

下载固定仓库、指定版本的主脚本与 `SHA256SUMS`，核对 GitHub 发布附件的 SHA256 及清单，并检查 Bash 语法、版本和自检结果。通过后在同一目录原子替换，旧脚本保留为 `manager.previous.sh`；替换后自检失败时回退，若回退无法写入则明确报错并保留备份。拒绝未托管目录、异常文件或符号链接。网络/API 限额、附件缺失、校验错误和写入权限不足会停止更新；不会改写节点配置、UUID、密钥、语言、Xray 核心、服务、防火墙或 BBR 参数。

成功后退出旧菜单，重新输入 `xr` 使用新版。备份只保留上一次更新前的脚本；更新本地源码目录请使用 Git 或下载完整源码包。直接运行而未安装的脚本需先执行 `install.sh`，此入口仅更新托管安装位置，不修改任意源文件。

## 防火墙与 BBR

入口为 **12 → 防火墙 / BBR**。菜单按防火墙（1–5）和 BBR（6–8）分组，每项单独一行：

- **1**：查看 UFW/firewalld 状态；firewalld 同时显示默认区域和活动区域。
- **2**：安装并启用 UFW。先检查已有防火墙和原生 netfilter 规则，再确认 SSH 端口（不假设为 22）、自动合并当前 `SSH_CONNECTION` 的服务端口与已安装节点端口，并允许填写其他需要保留的 TCP 端口，例如网站 80/443。预览并输入 `y` 后，通过 APT 安装缺少的 UFW，先添加放行规则，再设置默认拒绝入站、允许出站并启用。已有活跃防火墙、受支持 Fail2ban 结构以外的实际原生规则、拒绝策略、拒绝/限速/路由 UFW 规则或 IPv6 配置异常时停止，不覆盖。启用失败会尝试恢复未启用状态；若回退也失败，明确提示通过服务商控制台处理。规则、默认配置和已安装软件包可能保留，供核对和重试。
- **3 / 4**：放行全部已安装节点的 TCP 端口，或指定一个 1–65535 的 TCP 端口。执行前展示端口并要求输入 `y`。firewalld 可填写区域，回车使用默认区域；请确保它对应公网网卡。仅操作已启用的一个 UFW 或 firewalld；未启用、同时启用两者或无法识别状态时停止。不会安装/启停防火墙、清空规则、修改默认策略、删除端口或改动 SSH。firewalld 分别更新运行时和永久规则，不执行全局 reload。失败时可能已有部分放行，请检查状态后重试。
- **5**：停用/卸载 UFW。子菜单 **1** 仅停用，保留软件包与规则配置；**2** 卸载软件包并保留规则配置；**3** 卸载并清除 UFW 规则配置，清除后不可恢复。卸载前检查软件包状态、依赖与锁，经 `y` 确认后停用并验证，再仅操作 `ufw` 软件包。第 3 项使用 `dpkg --purge ufw`，也可清理第 2 项留下的配置；未安装且无 dpkg 配置记录时不清理未知文件。软件包被保留、状态不完整或存在依赖冲突时停止；停用失败不继续卸载。清除失败会报告可能已部分删除，且不会自动重新启用。使用只读模拟预检，不强制依赖、不 autoremove、不连带移除其他包。其他防火墙、iptables/nftables 工具、云安全组、节点、SSH 和 BBR 配置不在清理范围内；不直接清空全局规则。停用 UFW 后，原先被阻止的端口可能可达。
- **6 / 7 / 8**：查看 BBR 状态、启用 BBR 与 fq 默认参数、恢复启用前参数。只使用内核已有的 BBR（必要时尝试加载 `tcp_bbr` / `sch_fq` 模块），不安装或更换内核。原参数保存在本脚本独立文件 `/etc/sysctl.d/90-skybyte-xray-bbr.conf` 的注释中；拒绝覆盖其他内容或符号链接。重复启用保留最初记录，普通应用失败时尝试回退；回退未完成会保留文件并报错，可再次恢复。

支持 **Fail2ban 与 UFW 共存**：支持独立 `inet/f2b-table` 中的 `f2b-chain`（filter/input、优先级 -1、ACCEPT 默认策略），规则须只针对 TCP 端口和 IPv4/IPv6 封禁地址集合执行拒绝或丢弃。按完整结构验证，不能仅凭表名跳过检查；自定义跳转、放行、NAT、其他原生规则及 iptables 版 Fail2ban 仍须手动核对。确认前显示共存提示；启用或回退 UFW 后核对原有封禁结构保留，容许正常封禁地址与计数变化。未确认保留时报告检查 Fail2ban，并尝试停用 UFW；不会自动清空、停止或重建 Fail2ban。已有封禁仍可能阻止连接，启用后仍须测试新的 SSH 会话。

BBR 状态会先醒目显示“已开启 BBR 加速”或“未开启 BBR 加速”，终端中分别用绿色或黄色突出，再显示当前算法、默认队列、可用算法和管理状态。结论以运行中的拥塞控制算法为准；仅列为可用或存在持久化配置不代表已开启。

BBR 修改的是系统 TCP 默认拥塞控制，主要作用于新连接，不能保证提速。`net.core.default_qdisc=fq` 是默认队列设置，不会直接替换已有网卡队列；其他系统启动配置可能覆盖这些值，重启后请再次查看状态。恢复操作还原启用前的运行时参数并移除本脚本文件，原有的其他 sysctl 文件保持不变。卸载管理器保留防火墙规则和 BBR 设置；需要恢复 BBR 时应先执行 **12 → 8**。

本版同时修复首次添加规则的位置错误：使用 UFW 的 `prepend allow`，兼容 IPv4/IPv6 空规则列表；旧版 `insert 1` 在列表为空时会被 UFW 0.36.2 拒绝。UFW 失败提示会显示具体命令、退出码和经过筛选的错误分类，不输出外部异常中的敏感内容。

本版修复了空表误判：通过 nft JSON 区分表、链、规则和策略。无规则的空表、ACCEPT 默认链和未引用的空用户链不会单独阻止安装；除上述受支持的 Fail2ban 结构外，实际规则（含 ACCEPT/NAT）、DROP 策略、集合或无法识别的状态仍停止初始化，并显示具体检查命令、表/链或对象。检查失败不会清空或绕过规则。旧版的“可能属于 Docker”提示并不表示已经确定规则来源。

启用 UFW 前请确认全部需要的 TCP 端口，未放行的服务可能被阻断；此安装入口不处理额外 UDP 服务。启用后保留当前 SSH 会话，再新开一个连接验证访问。服务商控制台是故障恢复入口，系统命令成功不能替代实际 SSH 验证。

主机放行不等于公网连通：服务商安全组、UFW 的 IPv6 配置、规则优先级、firewalld 区域、CDN 端口支持仍需核对。本功能不直接编辑原生 nftables/iptables 规则。接口及故障场景使用隔离命令模拟器测试，不能替代实际 VPS 防火墙、内核和重启验收。

参考：[UFW 手册](https://manpages.ubuntu.com/manpages/noble/man8/ufw.8.html)、[firewalld 手册](https://firewalld.org/documentation/man-pages/firewall-cmd.html)、[Linux TCP 参数](https://kernel.org/doc/html/latest/networking/ip-sysctl.html)、[默认队列参数](https://www.kernel.org/doc/html/latest/admin-guide/sysctl/net.html)。

## 域名 TLS 和 CDN

1. 准备覆盖连接域名的可信 fullchain 和匹配私钥。证书必须包含对应 DNS SAN、系统可验证的信任链，且剩余有效期超过 24 小时。
2. 选择安装选项 3，填写连接地址、证书域名、证书与私钥的绝对路径。脚本验证证书并保存私密副本，不改写源文件。
3. 直连时让域名解析到 VPS。使用 CDN 时，在提供商后台配置 DNS 代理、受支持 HTTPS 端口、回源地址与严格的回源证书验证；XHTTP 路径不得被缓存、挑战页或其他规则改写。
4. Cloudflare 支持包括 443、2053、8443 在内的特定 HTTPS 端口，具体以 [官方端口说明](https://developers.cloudflare.com/fundamentals/reference/network-ports/) 为准。使用流式模式时还需核对平台对 gRPC/HTTP2 的支持。默认不使用自签名证书，不生成跳过验证的链接。

证书签发与续期由已有证书工具完成。外部证书续期后，进入 **5 → 3** 重新导入新 fullchain/私钥，保留节点凭据并重启此前运行中的服务。私密副本不会随着外部证书自动变化。

Reality 模式直连源站，不通过普通 HTTPS CDN 转发。测试 target 的 TLS 1.3/HTTP2 可达性不等于客户端公网连接、抗封锁或速度已验证。

选择 XHTTP-Reality 时无需自己的域名和证书，当前基础配置不添加 Vision flow。建议先使用 Xray 的 XMUX 默认值，不额外叠加 `mux.cool`，再按线路和客户端实测调整；不保证解决运营商限速或断流。

本版 TLS 由 Xray 直接终止。Nginx/Caddy 自动部署、自动签发续期、XMUX 自定义界面和 H3 选择尚未集成。自行前置真实网站可减少直接暴露代理服务的特征，但不能保证完全隐藏。HTTP/3 需要客户端、对端支持及 UDP 可达；通过 CDN 时客户端可用 H3，而回源仍可使用 H2，不需要仅为此让源站监听 QUIC。

## 导出与客户端

配置目录为 `/etc/skybyte-xray/`，包含：

- `nodes.txt`：通用 VLESS URI，协议之间按终端虚线分隔。
- `subscription-base64.txt`：本地 Base64 节点集合。
- `client-vision.json`、`client-xhttp-reality.json`、`client-xhttp-tls.json`：每种节点的完整 Xray 客户端配置，SOCKS 入口仅监听 `127.0.0.1:10808`。

这是本地导出，未托管为 HTTPS 在线订阅。文件可通过 SSH/SFTP 取回。客户端需要支持所选传输；二维码导入不会补全客户端对 XHTTP 的支持。不要把含 UUID、公钥凭据、私钥、完整链接或二维码的文件和截图公开。

Xray v26.3.27 与 v26.10.10 客户端/服务端在隔离环境的四种连接组合已互通；本版下载器保持正式版通道。原版 sing-box 1.14.3 的 Vision 与本版默认核心连接通过，但原版 sing-box 没有 XHTTP 传输。Mihomo 1.19.32 的 XHTTP-TLS/packet-up 实验通过，Reality 实验未通过，暂不承诺该组合兼容。小火箭及 v2rayN/v2rayNG 的真实 GUI 导入仍需实测。客户端、内核版本和传输方式需分别核对。

## 配置保护与维护

- 自有配置目录与核心目录权限 700，凭据、导出、证书副本和备份权限 600；私钥不进入命令参数。
- 服务为 `skybyte-xray.service`；核心与管理器在 `/usr/local/lib/skybyte-xray/`。不接管官方 `xray.service`、sing-box 或其他面板配置。
- 添加节点检查托管端口与当前监听占用。非托管文件冲突、符号链接或未知服务会拒绝覆盖。
- 候选配置经官方核心检查后应用。配置与服务单元有恢复事务；重启失败回退配置、活动状态和开机自启状态。下次启动可恢复未完成事务。
- 核心更新先检查配置；失败恢复旧核心。删除最后一个协议时停止并禁用本服务。
- 默认阻止节点访问本地回环、常见内网及链路本地目标，域名目标先解析再匹配规则。包括私网域名在内的拒绝行为有实际连接回归测试。
- 备份含 UUID、Reality 私钥及 TLS 私钥，须保密。恢复只读取已知数据结构，不执行备份中的代码或二进制；拒绝路径穿越、软硬链接、重复条目和超大文件。
- 卸载前必须成功备份，仅删除可识别的托管文件；保留备份、未知文件、外部证书、系统依赖和防火墙规则。

曾部署早期 development 测试版的用户：更新管理脚本不会自动改写运行中的配置。先备份，再在 **5 → 1** 对已安装节点重命名（名称可保持不变），可保留 UUID/密钥并重新生成配置，应用域名封锁修复。若手动编辑过 `config.json`，应另外保存原文件并核对自定义配置；状态备份不能保留未纳入管理器的自定义字段。

## 开发与测试

主源码：`src/manager.sh`（Bash 操作和界面）、`src/core.py`（配置、校验、下载和恢复）。生成的 `xray-manager.sh` 自包含 Python helper，不依赖旁边的源码文件。

```bash
python3 scripts/build.py
python3 scripts/build.py --check
bash -n install.sh
bash -n src/manager.sh
bash -n xray-manager.sh
shellcheck install.sh src/manager.sh xray-manager.sh
bash xray-manager.sh --self-check
XRAY_BIN=/absolute/path/to/verified/xray python3 -m unittest discover -s tests -v
```

本地使用已验证摘要的官方 Darwin/arm64 核心进行了配置检查与真实代理连接测试，涵盖 Vision、XHTTP-Reality、验证证书的 XHTTP-TLS 及 packet-up 源站模式。服务事务测试使用隔离的 systemctl 模拟器，**不能替代真实 systemd 开机测试**。packet-up 本地源站连接也不能代表已验证公网 CDN。

GitHub Actions 覆盖 Ubuntu 24.04、Debian 12、Debian 13；本地测试通过与 Linux CI 结果分别记录，不能用前者代替后者。实际 VPS、云防火墙、CDN 和客户端 GUI 导入仍需在测试服务器验证。

本轮代码检查、已修复问题及后续优化顺序见[项目检查记录](docs/REVIEW.md)。

品牌：SKYBYTE Manager · [订阅 SKYBYTE YouTube 频道](https://www.youtube.com/@SKYBYTE9119)。

## 许可证

Copyright © 2026 SKYBYTE (skylink9119)。管理脚本以 [GPLv3](LICENSE) 发布；分发修改版时保留版权与许可证声明，并按 GPL 提供源码。Xray-core 等独立第三方组件遵循各自许可证。
