# shellcheck shell=bash
ipv6_engine(){
 python3 - xray "$SKYBYTE_XRAY_DIR" '' "$@" <<'PY_IPV6'
# BUILD_IPV6_PY
import sys
try:ipv6_cli(*sys.argv[1:])
except (ValueError,OSError,KeyError,subprocess.SubprocessError) as error:
 print(str(error),file=sys.stderr);sys.exit(1)
PY_IPV6
}
ipv6_menu(){
 local choice candidates selected stage readiness=no
 if [[ $# == 0 || $1 == --menu ]];then
  menu 'IPv6 备用入口\n1 查看 IPv6 备用状态\n2 检测并启用 IPv6 备用入口\n3 移除 IPv6 备用入口（保留原节点）\n0 返回' 'IPv6 backup entry\n1 Show IPv6 backup status\n2 Detect and enable IPv6 backup\n3 Remove IPv6 backup (keep original nodes)\n0 Back'
  [[ ${1:-} != --menu ]] || return 0
  choice=$(ask '> ' '> ') || return 0
 else choice=$1;fi
 case $choice in
  1) report_output ipv6_engine status;;
  2)
   candidates=$(ipv6_engine detect) || return 1
   say "本机可用公网 IPv6：" "Available native IPv6:"
   printf '%s\n' "$candidates"
   selected=$(ask '备用 IPv6（回车使用第一个）：' 'Backup IPv6 (Enter uses first): ') || return 0
   selected=${selected:-${candidates%%$'\n'*}}
   helper node-ports >/dev/null && ipv6_engine check "$selected" || return 1
   warn '保留原地址、UUID、密钥、端口和 SNI，启用双栈监听并额外导出 IPv6 备用节点；CDN 节点保持不变。客户端网络必须支持 IPv6，云防火墙需放行实际 IPv6 端口。参数及链接保存在当前 VPS，请勿公开。' 'Keeps original addresses, UUIDs, keys, ports and SNI. Enables dual-stack and exports IPv6 backup nodes; CDN nodes are preserved. Client IPv6 and provider IPv6 firewall rules are required. Exports remain private on this VPS.'
   confirm '启用 IPv6 备用入口并重载正在运行的节点？' 'Enable IPv6 backup and reload running nodes?' || return 0
   stage=$(helper ipv6-prepare --address "$selected") || return 1
   readiness=ipv6
   apply_stage "$stage" no "$readiness" || return 1
   if [[ $(helper ufw-state) == active ]];then
    helper firewall-allow || return 1
   fi
   report_output ipv6_engine status
   say '重新导入节点后选择“IPv6备用”。已验证本地监听；公网连通需从有 IPv6 的客户端测试。未运行的服务保持停止。' 'Re-import and select the IPv6 backup node. Local listeners checked; test public ingress from an IPv6 client. Stopped services remain stopped.';;
  3)
   confirm '移除 IPv6 备用链接并恢复启用前的监听方式？原节点凭据保持不变。' 'Remove IPv6 backup links and restore previous listeners, keeping credentials?' || return 0
   stage=$(helper ipv6-prepare --disable) || return 1
   apply_stage "$stage" || return 1
   report_output ipv6_engine status;;
  0) return 0;;*) return 1;;
 esac
}
