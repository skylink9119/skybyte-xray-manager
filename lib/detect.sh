# lib/detect.sh — build-time module; assembled by scripts/build.py.
show_banner(){
 printf '%s\n============================================================\n' "$CYAN"
 cat <<'LOGO'
   ███████╗██╗  ██╗██╗   ██╗██████╗ ██╗   ██╗████████╗███████╗
   ██╔════╝██║ ██╔╝╚██╗ ██╔╝██╔══██╗╚██╗ ██╔╝╚══██╔══╝██╔════╝
   ███████╗█████╔╝  ╚████╔╝ ██████╔╝ ╚████╔╝    ██║   █████╗
   ╚════██║██╔═██╗   ╚██╔╝  ██╔══██╗  ╚██╔╝     ██║   ██╔══╝
   ███████║██║  ██╗   ██║   ██████╔╝   ██║      ██║   ███████╗
   ╚══════╝╚═╝  ╚═╝   ╚═╝   ╚═════╝    ╚═╝      ╚═╝   ╚══════╝
LOGO
 printf '               SKYBYTE Xray Manager v%s\n                Reality · Vision · XHTTP\n' "$VERSION"
 printf '============================================================%s\n' "$RESET"
}
OVERVIEW_CACHE=''
OVERVIEW_CACHE_AT=-10
OVERVIEW_CACHE_LANGUAGE=''
show_startup_info(){
 if [[ $OVERVIEW_CACHE_LANGUAGE != "$LANGUAGE" ]] || (( SECONDS - OVERVIEW_CACHE_AT >= 5 )); then
  if ! OVERVIEW_CACHE=$(helper overview --language "$LANGUAGE"); then
   OVERVIEW_CACHE=$(say '状态概览暂不可用，可通过菜单 d 或 l 查看详情。' 'Overview unavailable; use menu d or l for details.')
  fi
  OVERVIEW_CACHE_AT=$SECONDS
  OVERVIEW_CACHE_LANGUAGE=$LANGUAGE
 fi
 separator
 report_output printf '%s\n' "$OVERVIEW_CACHE"
 separator
}

environment_check(){
 (( EUID == 0 )) || { error '请以 root 账户运行。' 'Run as root.'; return 1; }
 [[ $(uname -s) == Linux && -d /run/systemd/system ]] || { error '需要 Linux 和 systemd。' 'Linux with systemd is required.'; return 1; }
 [[ -r /etc/os-release ]] || return 1
 local os_id
 os_id=$(awk -F= '$1=="ID" {gsub(/"/,"",$2);print $2}' /etc/os-release)
 [[ $os_id == ubuntu || $os_id == debian ]] || { error '仅支持 Ubuntu/Debian。' 'Ubuntu/Debian only.'; return 1; }
}
install_check_engine(){ python3 - "$@" <<'PY_INSTALL_CHECKS'
# BUILD_PREFLIGHT
PY_INSTALL_CHECKS
}
install_environment_check(){
 local options=(--project xray --language "$LANGUAGE" --phase environment)
 [[ ${1:-vision} == xhttp-tls ]] || options+=(--reality)
 report_output install_check_engine "${options[@]}" --paths "$SKYBYTE_XRAY_DIR" "$SKYBYTE_XRAY_LIB" "${TMPDIR:-/tmp}"
}
install_port_check(){
 report_output install_check_engine --project xray --language "$LANGUAGE" --phase ports --listen "$2" --tcp-port "$1"
}
install_download_check(){
 local options=(--project xray --language "$LANGUAGE" --phase download)
 [[ ! -x $SKYBYTE_XRAY_BINARY || -L $SKYBYTE_XRAY_BINARY ]] || options+=(--existing-core)
 report_output install_check_engine "${options[@]}"
}
install_reality_target(){
 helper reality-input --target "$2" --sni "$1" || return 1
 say '正在检查 Reality 目标的 DNS、TCP、TLS 与证书（总时限 12 秒）……' 'Checking Reality target DNS, TCP, TLS and certificate (12-second deadline)…'
 if ! report_output reality_engine --project xray --language "$LANGUAGE" --target "$2" --sni "$1";then
  error 'Reality 握手目标检测未通过；请更换网站或修复 VPS 出站网络、DNS、时间与 CA 证书后重试。尚未写入新节点。' 'Reality target failed checks; change the target or repair VPS egress, DNS, clock and CA roots. No new node was written.'
  return 1
 fi
}
installation_check_menu(){
 local choice kind node_port listen sni target
 if [[ $# == 0 || $1 == --menu ]];then
  menu '节点安装前检测（不安装）\n1. TCP + Reality + Vision\n2. XHTTP + Reality\n3. XHTTP + TLS（系统/端口/下载检测）\n0. 返回' 'Node installation checks (no installation)\n1. TCP + Reality + Vision\n2. XHTTP + Reality\n3. XHTTP + TLS (system/port/download checks)\n0. Back'
  [[ ${1:-} != --menu ]] || return 0
  choice=$(ask '> ' '> ') || return 0
 else choice=$1;fi
 case $choice in 1)kind=vision;node_port=443;;2)kind=xhttp-reality;node_port=443;;3)kind=xhttp-tls;node_port=2053;;0)return 0;;*)return 1;;esac
 local entered
 entered=$(ask "TCP 端口 [$node_port]：" "TCP port [$node_port]: ") || return 0;node_port=${entered:-$node_port}
 listen=$(ask '监听：1 IPv4  2 双栈 IPv4+IPv6 [1]：' 'Listen: 1 IPv4  2 Dual-stack IPv4+IPv6 [1]: ') || return 0
 case ${listen:-1} in 1)listen=0.0.0.0;;2)listen=::;;*)return 1;;esac
 install_environment_check "$kind" && install_port_check "$node_port" "$listen" || return 1
 if [[ $kind != xhttp-tls ]];then
  sni=$(choose_reality_sni) || return 1;[[ -n $sni ]] || return 0
  target=$(ask "握手目标 [$sni:443]：" "Handshake target [$sni:443]: ") || return 0;target=${target:-$sni:443}
  install_reality_target "$sni" "$target" || return 1
 fi
 install_download_check
}
