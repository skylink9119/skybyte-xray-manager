# modules/warp.sh — build-time module; assembled by scripts/build.py.
warp_choose_profile(){
 local selection profile domains
 menu '分流平台\n1 Netflix + Disney+ + ChatGPT + Gemini（默认）\n2 仅 Netflix\n3 仅 Disney+\n4 仅 ChatGPT\n5 仅 Gemini\n6 自定义域名后缀\n0 返回' 'Routing profile\n1 Netflix + Disney+ + ChatGPT + Gemini (default)\n2 Netflix only\n3 Disney+ only\n4 ChatGPT only\n5 Gemini only\n6 Custom domain suffixes\n0 Back' >&2
 selection=$(ask '选择 [1]：' 'Choose [1]: ') || return 1
 case ${selection:-1} in
  1) profile=all;; 2) profile=netflix;; 3) profile=disney;; 4) profile=chatgpt;; 5) profile=gemini;;
  6) domains=$(ask '域名后缀（空格分隔，不含通配符）：' 'Domain suffixes (space-separated, no wildcards): ') || return 1
     [[ -n $domains ]] || return 1; printf '%s\n' "$domains"; return;;
  *) return 1;;
 esac
 helper warp-profile --profile "$profile"
}
warp_apply(){
 local proxy_port=$1 domains stage
 local suffixes=()
 helper node-ports >/dev/null || return 1
 domains=$(warp_choose_profile) || return 0
 read -r -a suffixes <<< "$domains"
 warn '仅匹配的 TCP 域名流量使用 WARP，其余流量直连；匹配的 UDP 拒绝以便应用回退 TCP。WARP 出口通过不代表平台解锁。' 'Only matching TCP domains use WARP; other traffic stays direct. Matching UDP is blocked for TCP fallback. Verified WARP egress does not prove platform access.'
 confirm '应用 WARP 分流并重启原先运行的节点？' 'Apply WARP routing and restart previously running nodes?' || return 0
 helper warp-check --proxy-port "$proxy_port" || return 1
 stage=$(helper warp-prepare --proxy-port "$proxy_port" --domains "${suffixes[@]}") || return 1
 apply_stage "$stage" || return 1
 say 'WARP 分流已应用。可用选项 5 对比直连与 WARP 的平台响应。' 'WARP routing applied. Use option 5 to compare direct and WARP platform responses.'
}
warp_install_client(){
 local os_id code proxy_port tmp item listeners attempt ready=0
 helper node-ports >/dev/null || return 1
 if command -v warp-cli >/dev/null; then
  warn '已安装 WARP 客户端，请选择“使用已有本机代理”，保留现有注册和设置。' 'WARP is already installed; use the existing local proxy option to retain registration and settings.'
  return 1
 fi
 if [[ -e ${SKYBYTE_WARP_DATA_DIR:-/var/lib/cloudflare-warp} || -L ${SKYBYTE_WARP_DATA_DIR:-/var/lib/cloudflare-warp} ]]; then
  error '发现已有 WARP 数据，请先手动核对注册与模式，避免启动已有全局连接。' 'Existing WARP data found; inspect registration and mode before starting a potentially global connection.'
  return 1
 fi
 os_id=$(awk -F= '$1=="ID" {gsub(/"/,"",$2);print $2}' /etc/os-release)
 code=$(awk -F= '$1=="VERSION_CODENAME" {gsub(/"/,"",$2);print $2}' /etc/os-release)
 case $os_id:$code in ubuntu:jammy|ubuntu:noble|ubuntu:resolute|debian:bookworm|debian:trixie) ;; *) error '当前系统版本不在官方 WARP 自动安装支持列表中。' 'This OS release is not supported for automatic WARP installation.'; return 1;; esac
 local repo=/etc/apt/sources.list.d/skybyte-xray-cloudflare-warp.list key=/usr/share/keyrings/skybyte-xray-cloudflare-warp.gpg
 for item in "$repo" "$key"; do [[ ! -e $item && ! -L $item ]] || { error 'WARP 软件源文件已存在，请先核对。' 'WARP repository files already exist; inspect them first.'; return 1; }; done
 say '安装官方 Cloudflare WARP，仅启用本机代理模式。条款：https://www.cloudflare.com/application/terms/ 。卸载管理器会保留 WARP 软件和连接。' 'Install official Cloudflare WARP in local proxy mode. Terms: https://www.cloudflare.com/application/terms/ . Removing the manager retains WARP and its connection.'
 confirm '安装、注册并接受 WARP 条款？' 'Install, register and accept WARP terms?' || return 0
 proxy_port=$(ask '本机 SOCKS5 端口 [40000]：' 'Local SOCKS5 port [40000]: ') || return 0
 proxy_port=${proxy_port:-40000}
 [[ $proxy_port =~ ^[0-9]{4,5}$ ]] && ((10#$proxy_port>=1024 && 10#$proxy_port<=65535)) || return 1
 proxy_port=$((10#$proxy_port))
 # Validate node collisions before installing packages or writing repository files.
 python3 - "$SKYBYTE_XRAY_DIR/state.json" "$proxy_port" <<'PY_WARP_PORT' || return 1
import json,sys
assert all(n['port']!=int(sys.argv[2]) for n in json.load(open(sys.argv[1]))['nodes'].values()), 'Proxy conflicts with a node port / 代理与节点端口冲突'
PY_WARP_PORT
 apt_refresh && apt-get install -y curl ca-certificates gnupg iproute2 || return 1
 listeners=$(ss -H -ltn "( sport = :$proxy_port )") || return 1
 [[ -z $listeners ]] || { error '代理端口已被占用。' 'Proxy port is occupied.'; return 1; }
 tmp=$(mktemp -d "$SKYBYTE_XRAY_DIR/.warp-install.XXXXXX") || return 1
 if ! curl -q -fsSL --noproxy '*' --proto '=https' --proto-redir '=https' --max-time 30 https://pkg.cloudflareclient.com/pubkey.gpg -o "$tmp/key" ||
    ! gpg --batch --yes --dearmor --output "$tmp/keyring" "$tmp/key"; then rm -rf -- "$tmp"; return 1; fi
 install -m 644 "$tmp/keyring" "$key" || { rm -rf -- "$tmp"; return 1; }
 printf 'deb [signed-by=%s] https://pkg.cloudflareclient.com/ %s main\n' "$key" "$code" > "$repo"
 chmod 644 "$repo"; rm -rf -- "$tmp"
 apt_refresh && apt-get install -y cloudflare-warp || return 1
 systemctl enable --now warp-svc.service || return 1
 if warp-cli --accept-tos registration show >/dev/null 2>&1; then
  error '发现已有 WARP 注册，保留现有设置，请手动配置代理后选择选项 2。' 'Existing WARP registration found; retained. Configure its proxy manually and choose option 2.'; return 1
 fi
 warp-cli --accept-tos registration new >/dev/null && warp-cli --accept-tos mode proxy && warp-cli --accept-tos proxy port "$proxy_port" && warp-cli --accept-tos connect || return 1
 for ((attempt=0; attempt<3; attempt++)); do
  if helper warp-check --proxy-port "$proxy_port"; then ready=1; break; fi
  sleep 2
 done
 ((ready)) || { error 'WARP 尚未就绪，节点分流未改变。可稍后选择选项 2 重试。' 'WARP is not ready; node routing is unchanged. Retry with option 2 later.'; return 1; }
 warp_apply "$proxy_port"
}
warp_menu(){
 local choice proxy_port stage
 # --menu renders only; a numeric argument executes one selected operation.
 if [[ $# == 0 || $1 == --menu ]]; then
 printf '\n%s%s%s\n' "$CYAN" "$(if [[ $LANGUAGE == en ]]; then printf '========== WARP Manager =========='; else printf '========== WARP 管理 =========='; fi)" "$RESET"
 report_output helper warp-status --language "$LANGUAGE" || return 1
 menu '
【代理设置】
1. 安装官方 WARP 本机代理

【分流设置】
2. 使用已有代理 / 选择分流平台
3. 关闭 WARP 分流，恢复直连

【连接检测】
4. 验证 WARP 出口
5. 对比直连 / WARP 平台响应
6. 专业流媒体 / 回程 / 测速

0. 返回
--------------------------------------' '
[Proxy setup]
1. Install official WARP local proxy

[Routing]
2. Existing proxy / choose platforms
3. Disable WARP routing, restore direct

[Connection tests]
4. Verify WARP egress
5. Compare direct / WARP platform responses
6. Professional media / routes / speed tests

0. Back
--------------------------------------'
 [[ ${1:-} != --menu ]] || return 0
 choice=$(ask '> ' '> ') || return 0
 else
  choice=$1
 fi
 case $choice in
  1) warp_install_client;;
  6) media_check --interactive;;
  2|4|5)
   proxy_port=$(ask '本机 SOCKS5 端口 [40000]：' 'Local SOCKS5 port [40000]: ') || return 0
   proxy_port=${proxy_port:-40000}
   case $choice in 2) warp_apply "$proxy_port";; 4) helper warp-check --proxy-port "$proxy_port";; 5) warp_platform_test "$proxy_port";; esac;;
  3) confirm '关闭本项目 WARP 分流？WARP 软件和其他项目保持原样。' 'Disable WARP routing for this project? WARP and other projects are retained.' || return 0
     stage=$(helper warp-prepare --disable) || return 1
     apply_stage "$stage";;
  0) return 0;; *) return 1;;
 esac
}
