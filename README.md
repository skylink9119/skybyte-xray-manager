# SKYBYTE Xray Manager

[English](README_EN.md) · [YouTube](https://www.youtube.com/@SKYBYTE9119)

独立的 Bash VPS 管理工具，使用官方 Xray-core，支持 Ubuntu/Debian、中文和英文界面。首版本地测试版 **0.1.0**，默认核心 **v26.3.27**。本项目与 SKYBYTE Manager 的 sing-box 配置、二进制和服务使用不同路径，可在端口不冲突时共存。

## 三种节点

| 安装方式 | 传输与安全 | 默认 TCP 端口 | 准备条件 |
| --- | --- | --- | --- |
| VLESS + Reality + Vision | RAW/TCP + Reality，Vision flow | 443 | 可达、支持 TLS 1.3 和 HTTP/2 的握手目标 |
| VLESS + XHTTP + Reality | XHTTP + Reality，不混入 Vision flow | 8443 | 同上，无需自己的域名证书 |
| VLESS + XHTTP + TLS/CDN | XHTTP + TLS，默认开启验证 | 2053 | 自有域名、已有可信 fullchain 与匹配私钥 |

可依次安装三种节点，每种协议一个入口、不同 TCP 端口。重复安装已存在的协议会拒绝；重命名、更新证书和核心升级保留已有 UUID 与密钥。删除后重新安装会生成新凭据。

支持 IPv4 或 IPv6 监听，以及自定义客户端连接地址、端口、节点名和 XHTTP 路径。支持客户端 `auto`、`packet-up`、`stream-up`、`stream-one` 模式，服务端接受兼容的模式；CDN 模式默认 `packet-up`，拒绝在该模式选择 `stream-one`。参考 [Xray 的 XHTTP 说明](https://github.com/XTLS/Xray-core/discussions/4113) 和 [Reality 文档](https://xtls.github.io/config/transports/reality.html)。

## 安装

需要 **root、Ubuntu/Debian 和 systemd**；首版二进制支持 amd64、arm64。把完整源码包上传到 VPS，解压后进入项目目录，执行：

```bash
bash install.sh
```

也可在完整目录直接运行 `bash xray-manager.sh`。无需 sudo。缺少 Python 或 flock 时，安装入口会询问是否安装基础依赖。APT 索引更新失败会停止，不继续使用旧索引安装。核心仅从官方稳定 Release 下载，并按 GitHub Release 的 SHA256 摘要验证。

独立仓库：[skylink9119/skybyte-xray-manager](https://github.com/skylink9119/skybyte-xray-manager)。首版代码在 `development` 分支，通过 PR 审核后再进入 `main`。完整包包含 `install.sh` 和自包含的 `xray-manager.sh`；不能只复制安装入口而漏掉主脚本。

首次启动选择语言。菜单和提问绿色加粗，节点信息黄色，链接和错误红色，警告黄色；非终端或 `NO_COLOR=1` 可关闭颜色。YES 确认不区分大小写。

## 菜单

| 选项 | 操作 |
| --- | --- |
| 1 | 安装或添加三种节点之一 |
| 2 | 查看节点链接与客户端导出文件 |
| 3 | 本地生成节点二维码 |
| 4 | 服务状态、启停、重启、配置检查与日志 |
| 5 | 重命名、删除协议、更新 TLS 证书 |
| 6 | 校验并更新官方稳定 Xray 核心 |
| 7 / 8 | 配置备份与恢复 |
| 9 / 10 / 11 | 使用说明、语言、卸载 |

需要在系统防火墙和服务商安全组放行实际 TCP 端口。本脚本不自动更改 UFW、SSH 端口或服务商安全组。

## 域名 TLS 和 CDN

1. 准备覆盖连接域名的可信 fullchain 和匹配私钥。证书必须包含对应 DNS SAN、系统可验证的信任链，且剩余有效期超过 24 小时。
2. 选择安装选项 3，填写连接地址、证书域名、证书与私钥的绝对路径。脚本验证证书并保存私密副本，不改写源文件。
3. 直连时让域名解析到 VPS。使用 CDN 时，在提供商后台配置 DNS 代理、受支持 HTTPS 端口、回源地址与严格的回源证书验证；XHTTP 路径不得被缓存、挑战页或其他规则改写。
4. Cloudflare 支持包括 443、2053、8443 在内的特定 HTTPS 端口，具体以 [官方端口说明](https://developers.cloudflare.com/fundamentals/reference/network-ports/) 为准。使用流式模式时还需核对平台对 gRPC/HTTP2 的支持。默认不使用自签名证书，不生成跳过验证的链接。

证书签发与续期由已有证书工具完成。外部证书续期后，进入 **5 → 3** 重新导入新 fullchain/私钥，保留节点凭据并重启此前运行中的服务。私密副本不会随着外部证书自动变化。

Reality 模式直连源站，不通过普通 HTTPS CDN 转发。测试 target 的 TLS 1.3/HTTP2 可达性不等于客户端公网连接、抗封锁或速度已验证。

## 导出与客户端

配置目录为 `/etc/skybyte-xray/`，包含：

- `nodes.txt`：通用 VLESS URI，协议之间按终端虚线分隔。
- `subscription-base64.txt`：本地 Base64 节点集合。
- `client-vision.json`、`client-xhttp-reality.json`、`client-xhttp-tls.json`：每种节点的完整 Xray 客户端配置，SOCKS 入口仅监听 `127.0.0.1:10808`。

这是本地导出，未托管为 HTTPS 在线订阅。文件可通过 SSH/SFTP 取回。客户端需要支持所选传输；二维码导入不会补全客户端对 XHTTP 的支持。不要把含 UUID、公钥凭据、私钥、完整链接或二维码的文件和截图公开。

## 配置保护与维护

- 自有配置目录与核心目录权限 700，凭据、导出、证书副本和备份权限 600；私钥不进入命令参数。
- 服务为 `skybyte-xray.service`；核心与管理器在 `/usr/local/lib/skybyte-xray/`。不接管官方 `xray.service`、sing-box 或其他面板配置。
- 添加节点检查托管端口与当前监听占用。非托管文件冲突、符号链接或未知服务会拒绝覆盖。
- 候选配置经官方核心检查后应用。配置与服务单元有恢复事务；重启失败回退配置、活动状态和开机自启状态。下次启动可恢复未完成事务。
- 核心更新先检查配置；失败恢复旧核心。删除最后一个协议时停止并禁用本服务。
- 默认阻止节点访问本地回环、常见内网及链路本地目标，防止使用节点访问服务器私有服务。
- 备份含 UUID、Reality 私钥及 TLS 私钥，须保密。恢复只读取已知数据结构，不执行备份中的代码或二进制；拒绝路径穿越、软硬链接、重复条目和超大文件。
- 卸载前必须成功备份，仅删除可识别的托管文件；保留备份、未知文件、外部证书、系统依赖和防火墙规则。

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

品牌：SKYBYTE Manager · [订阅 SKYBYTE YouTube 频道](https://www.youtube.com/@SKYBYTE9119)。

## 许可证

Copyright © 2026 SKYBYTE (skylink9119)。管理脚本以 [GPLv3](LICENSE) 发布；分发修改版时保留版权与许可证声明，并按 GPL 提供源码。Xray-core 等独立第三方组件遵循各自许可证。
