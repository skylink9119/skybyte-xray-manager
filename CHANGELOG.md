# Changelog

## 0.1.30 — 2026-10-30

- a → 5 新增独立 IPv6 安装入口：Vision、XHTTP+Reality 与直连 XHTTP+TLS；检测原生 IPv6、路由和防火墙后导出 IPv6 主地址节点。
- 已有同协议拒绝覆盖；其他协议保留。新端口本地监听失败回滚，活动 UFW 先放行再应用；新增规则保留供核对。
- 保留 l → 9 IPv6 备用入口与官方 v26.10.29 核心。

## 0.1.29 — 2026-10-30

- e → 5 新增独立修改节点端口入口，自动选择唯一已安装协议，显示当前端口、回车保留并确认后应用。
- 保留 UUID、密钥、Short ID、握手与路径，IPv6 备用同步更新；UFW 放行失败不切换端口，重载失败回滚。
- 官方核心仍为 v26.10.29。

## 0.1.28 — 2026-10-29

- IPv6 备用入口排除 WARP/WireGuard、TUN 等隧道网卡，避免把代理出口当作 VPS 原生入站地址。
- 保留 v0.1.27 的双栈备用功能与官方 v26.10.29 核心。

## 0.1.27 — 2026-10-29

- 新增 l → 9 IPv6 备用入口：本机地址/路由/防火墙与端口检查，双栈监听，保留原 IPv4 节点和凭据，额外导出 IPv6 链接及客户端 JSON。
- 支持移除备用入口恢复原监听；配置、服务、导出失败回滚，CDN 和回环节点不自动公开。
- 默认官方核心同步至 v26.10.29；保留新版 Freedom 私网目标保护，仅隔离测试环境使用精确端口例外。

## 0.1.26 — 2026-10-29

- 流媒体报告改为带边框的五列表格，长平台名、中文和错误说明按终端宽度对齐换行。
- 报告、资源与网络状态统一黄色；菜单保持绿色，保留 NO_COLOR 和重定向纯文本。
- 保留外部命令的终端连接与退出码；综合测评中的外部颜色重置不会改变报告颜色。

## 0.1.25 — 2026-10-29

- UnlockTests 替换旧 WARP 平台页面检测；新增 n → 6 专业检测菜单，支持全球+AI、全地区、直连 IPv4/IPv6 与 WARP 对比。
- 融合怪 Go 提供可选三网回程、测速和综合网络检测；关闭上传及 CPU/内存/磁盘压力，带宽测试先确认。
- 官方发布资源按需下载、校验 SHA256，缓存限量，检测进程/超时/私密报告独立管理；菜单保持快速打开。
- 选型与验证细节见 docs/PROFESSIONAL-DIAGNOSTICS.md。

## 0.1.24 — 2026-10-29

- 主菜单按节点、服务与网络、更新与备份、设置分组；子菜单一项一行，现有字母/数字入口不变。
- 拒绝执行空文件、HTML 错误页和语法错误的安装器；安装下载统一 HTTPS 与连接超时。
- 修复节点列表读取错误被进程替换吞掉的问题，失败不再显示导出成功提示，菜单保持可用。
- 无效编辑选项直接提示；取消协议选择返回编辑菜单；修正使用说明中 Reality 更换功能和更新入口提示。

## 0.1.23 — 2026-10-28

- Run startup service, core-version and UFW probes concurrently instead of stacking two-second waits. Preserve read-only local queries, ownership checks and credential filtering.
- Reuse a five-second in-memory overview for read-only menu returns; refresh after management actions, language changes or expiry. Cache failures briefly as well, so a broken probe does not repeatedly delay navigation.
- Add real stalled-command timeout coverage and menu cache/refresh regressions. No new resident service or change to forwarding configuration.
- Fix remaining installer/editor TCP TIME_WAIT false positives; preserve active-listener and managed-port conflict rejection. Reject encrypted server keys without interactive password prompts and bound certificate-chain commands.

## 0.1.22 — 2026-10-28

- Match core TCP bind behavior in preflight using SO_REUSEADDR, so a recently stopped service in TIME_WAIT does not falsely block installation. Active TCP listeners are still rejected; UDP checks remain exclusive.
- Add an actual local TCP close/rebind regression alongside the occupied TCP/available UDP checks.

## 0.1.21 — 2026-10-28

- Add a → 4 standalone installation checks and automatic preflight: OS/architecture/systemd, actual APT/DPKG locks, dependencies/PATH, storage, TCP binding, firewall reminders, detailed Reality DNS/TCP/TLS/certificate/HTTP2 checks, and bounded GitHub HTTPS checks. Failures stop before core download or new node generation.
- Check Reality/TLS inputs before downloading core; retain existing ownership, port and transaction safeguards. Standalone checks do not install dependencies or change firewall, services or node data.
- Shorten the installation command through sky9119.cc/xr.sh, an HTTPS redirect to the latest stable bootstrap asset; retain missing-curl support, failure/empty-body gating and subsequent digest verification.
- Add real POSIX-lock/TCP-UDP tests, bounded DNS/HTTPS simulations and failure-before-mutation integration checks.

## 0.1.20 — 2026-10-28

- Add read-only node parameters in main menu `p`: show UUID, public key, short ID, SNI, target, address and port for each installed node; distinguish TLS nodes without Reality.
- Remind users that sensitive data is stored on their VPS, to keep credentials/screenshots private and to install/enable a firewall after allowing SSH and node ports. Never display server private keys or regenerate exports for this view.
- Cover multiple nodes, missing nodes, bilingual output, menu navigation, ownership and read-only/privacy behavior.

## 0.1.19 — 2026-10-26

- Add Reality target replacement in `o → 3`: select an installed Vision or XHTTP/Reality node, choose a preset/custom SNI and target, pass DNS/TCP/TLS 1.3/certificate/HTTP/2 checks, then confirm with `y`.
- Preserve UUIDs, key pairs, short IDs, node ports, XHTTP paths/modes, routing and other nodes. Refresh client exports transactionally; restore files and prior service state if validation or restart fails. Failed checks and cancellation make no changes.
- Add regression coverage for replacement, independent targets/ports, credential retention, failed checks, cancellation, missing nodes and rollback.

## 0.1.18 — 2026-10-26

- Recognize the distinct `socket.timeout` exception used by Python 3.9, so a stalled Reality target is reported as a timeout rather than a local system failure. Add a compatibility regression without changing node configuration or TLS verification.

## 0.1.17 — 2026-10-26

- Add read-only Reality target checks in main menu `o`: inspect configured TCP/Reality and XHTTP/Reality targets or test a custom hostname/port/SNI before installation.
- Report DNS, connected TCP address, TLS 1.3, certificate trust/validity/name, HTTP/2 ALPN and a clear pass/fail summary with bounded network timeouts. Retain the current menu after checks; do not edit credentials, routes or services.
- Add local TLS regression coverage for TLS 1.2-only peers, absent HTTP/2, incorrect/untrusted certificates, expiry reasons, DNS/TLS timeouts, multiple targets and continuous menu navigation.

## 0.1.16 — 2026-10-24

- Use case-insensitive a–n main-menu entries and q to exit, numeric submenus and 0 to return one level. Keep previous main-menu numbers as compatibility aliases.
- Keep firewall/BBR, service, node-edit and WARP menus open after completed, cancelled or failed operations; EOF returns cleanly. Preserve existing firewall checks and node transaction rollback.
- Update bilingual help/navigation references and add continuous-operation, cancellation, failure and EOF regression checks.

## 0.1.15 — 2026-10-23

- Group WARP controls into proxy setup, routing and connection tests with one short option per line, preserving menu numbers.
- Localize and shorten WARP status to the mode, loopback proxy and suffix count instead of printing a long domain list.
- Verify bilingual newlines, 80-column layout, privacy and read-only status alongside existing routing/cancellation tests.

## 0.1.14 — 2026-10-23

- Show local server resources, actual Xray version, service/boot state, node ports, BBR and related components whenever the main menu opens; tolerate missing probes without network requests or configuration writes.
- Add menu 14 for official WARP local-proxy installation, existing SOCKS5 gateways, Netflix/Disney+/ChatGPT/Gemini/custom domain routing, verified egress and direct/WARP anonymous page comparisons.
- Preserve credentials, private-destination blocking and unmatched direct traffic; block matching UDP for TCP fallback, validate candidates and roll back failed service changes. Include routing in existing backup/restore transactions.
- Preserve existing WARP clients/data and other projects; add bounded readiness checks and explicit cancellation. WARP egress and page responses do not prove playback or account access.

## 0.1.13 — 2026-10-23

- Standardize manager and installer dependency confirmations as [y/N]; y/Y confirms, while Enter, n/N and invalid input cancel the action. CDN selection uses y/Y to enable and defaults to direct connections.
- Add a one-line curl bootstrap, pinned installer download, private temporary staging, syntax validation and cleanup; keep README commands and packaged assets synchronized.
- Cover affirmative, cancellation, invalid and EOF input, including node installation, CDN choice and installer dependencies.

## 0.1.12 — 2026-10-19

- Reuse the sing-box project's SKYBYTE ASCII logo in the Xray main menu, retaining bilingual text and NO_COLOR handling.
- Reject already-installed protocols and stopped managed-node port conflicts in read-only preflight, before target probes or core preparation.
- Refuse installer downgrades, mismatched payload versions and unknown installed versions before replacing files.
- Allow uninstalling the manager before any nodes or service unit exist, retaining backups and unknown files and stopping on failures for an existing owned service.
- Record the maintenance review and prioritize node diagnostics, runtime status, certificate expiry visibility and real VPS acceptance checks.

## 0.1.11 — 2026-10-19

- Default new XHTTP/Reality nodes to TCP 443 instead of 8443, retaining manual port selection and occupied-port checks.
- Replace ambiguous [YES] prompts with explicit type-YES/Enter-to-cancel instructions; report cancelled node installation normally without core preparation or node writes.
- Add numbered Reality handshake domain presets for Microsoft, Apple, Amazon, Cloudflare and Google, plus custom/direct input and a back option in both languages.
- Apply the selected SNI and matching default target to TCP/Reality and XHTTP/Reality, retaining target overrides and the existing preflight and TLS 1.3/HTTP/2 probe before installation.
- Cover default/custom selection, both Reality transports, cancellation, invalid input, failed probes and the separate TLS certificate flow.

## 0.1.10 — 2026-10-19

- Lead BBR status with a prominent enabled/not-enabled summary based on the running congestion control, with terminal colors and readable parameter labels instead of raw JSON.
- Distinguish active BBR from available algorithms or a saved configuration; status remains read-only after viewing, enabling or restoring settings.

## 0.1.9 — 2026-10-19

- Allow structurally validated independent Fail2ban nftables TCP input bans to coexist with UFW initialization, preserving IPv4/IPv6 address sets and existing bans.
- Preview coexistence, verify ban structure after activation or rollback, tolerate dynamic ban/counter updates, and keep custom/unknown/iptables firewall rules guarded.
- Add reported-layout and adversarial regressions plus real UFW/nft TCP checks in private network and mount namespaces in CI.

## 0.1.8 — 2026-10-19

- Group firewall menu actions as 1–5 and BBR actions as 6–8, with one action per line and updated recovery references.
- Add UFW submenu 3 to purge its package and rule configuration, including residual configuration after package removal, with explicit confirmation and matching read-only preflight.
- Fix empty optional firewall arguments under Bash 3.2 when allowing all node ports.
- Verify the purged package state, report partial cleanup failures, and cover cancellation, disable failures, config-only cleanup and bilingual menu dispatch without changing the host firewall.

## 0.1.7 — 2026-10-19

- Add menu 12 → 8 for disabling UFW or removing only its package while retaining rule configuration, with targeted warnings and explicit confirmation.
- Check package state/dependencies before disabling, verify inactivity before removal, refuse forced dependency changes, and report partial removal failures without automatic re-enable.
- Add isolated state/order/cancellation/failure regressions and a real dpkg no-act integration check that leaves the CI UFW package installed.

## 0.1.6 — 2026-10-19

- Fix first-run UFW rule insertion with prepend instead of insert 1; add real distribution frontend compatibility checks with an isolated backend.
- Report failed UFW commands, exit codes and safe error categories instead of generic core errors. CI installs the distro UFW package for frontend regression checks.

- Fix UFW initialization false positives from empty nft/iptables tables, default ACCEPT chains and unreferenced empty user chains, including tables created by iptables-nft inspection.
- Inspect nft JSON and report the exact command/table/chain or object that blocks setup; keep actual rules, DROP policies and unknown state protected.
- Add regressions for repeated inspection, ACCEPT/NAT/DROP conflicts, malformed output and safe diagnostic labels.

## 0.1.5 — 2026-10-19

- Add menu 12 → 7 to install missing UFW via APT and explicitly initialize/enable it after previewing confirmed SSH, current SSH session, node and extra TCP ports.
- Stage allow rules before applying deny-incoming/allow-outgoing defaults and activation. Refuse active firewalls, existing netfilter rules, restrictive stored UFW rules and unsafe IPv6 configuration.
- Attempt to disable a failed initial activation, report console recovery if rollback fails, and retain package/configuration for inspection. Add isolated activation-order, cancellation, package failure and SSH regressions.

## 0.1.4 — 2026-10-19

- Add menu 13 for stable-release manager updates with version preview, explicit confirmation, pinned repository/tag, release-asset and manifest SHA256 verification, syntax/version/self-check validation and atomic replacement.
- Preserve a previous-script backup and restore it on post-install validation failure; refuse foreign paths and downgrades against both running and installed versions.
- Preserve node credentials, core, services, firewall and BBR settings; exit the old menu after successful update. Add isolated integrity, replacement and bilingual menu regressions.

## 0.1.3 — 2026-10-19

- Add menu 12 for active UFW/firewalld status and explicit inbound TCP allows for managed or selected ports, without firewall enable/disable/reset or global reload.
- Add BBR status, existing-kernel enablement and restoration of saved runtime defaults through a guarded dedicated sysctl file; detect failed application and attempt rollback.
- Add isolated firewall, kernel parameter and bilingual confirmation regressions; preserve TCP/Reality Vision defaults and unchanged XHTTP exports.

## 0.1.2 — 2026-10-19

- Edit installed node addresses, TCP ports and XHTTP paths while preserving credentials and TLS certificates.
- Validate changed ports, regenerate client exports and reuse configuration rollback; keep stopped services stopped and skip empty edits.
- Add editing, export consistency, bilingual menu and failed-restart recovery regressions.

## 0.1.1 — 2026-10-15

- Add the SKYBYTE YouTube subscription invitation and owner-supplied VPS affiliate links to both READMEs.
- Require the public client address, re-prompt empty input and check TCP port availability before target probes or core downloads.
- Explain occupied ports, permissions, missing files, disk space and download/TLS failures without exposing external exception secrets; preserve existing services and configurations.
- Add installation-input, port-conflict and diagnostic-redaction regressions; publish matching source archives and installer metadata.

## 0.1.0 — 2026-10-15

- Independent Bash manager with Chinese/English SKYBYTE interfaces.
- Reality/Vision, XHTTP-Reality and verified domain XHTTP-TLS/CDN configuration.
- Official SHA256-verified core downloads; separate ownership, paths and service.
- Credential-preserving rename/certificate refresh; local URI, Base64, Xray JSON and QR exports.
- Service controls, configuration/core rollback, recovery journal, private backups and guarded uninstall.
- Standalone one-command installer with pinned payload SHA256 verification and guarded xr shortcut.
- Resolve hostname destinations before private-IP routing checks; authenticated regression coverage for private IP and hostname blocking.
- Installer integrity, ownership preservation, shortcut and uninstall regressions; source-only release packaging with checksums.
- Chinese/English deployment guidance and explicit XHTTP, H3 and client compatibility boundaries.
- Ubuntu 24.04, Debian 12 and Debian 13 CI with verified official core and authenticated proxy tests.
