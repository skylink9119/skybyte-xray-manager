# lib/firewall.sh — build-time module; assembled by scripts/build.py.
firewall_open(){
 local value=${1:-} zone
 local flags=()
 [[ -z $value ]] || flags+=(--ports "$value")
 report_output helper firewall-status || return 1
 zone=$(ask 'firewalld 区域 [回车使用默认区域；UFW 忽略]：' 'firewalld zone [Enter for default; ignored by UFW]: ') || return 1
 [[ -z $zone ]] || flags+=(--zone "$zone")
 warn '只向已启用的 UFW/firewalld 添加入站 TCP 放行，不改 SSH 或默认策略。请同时检查服务商安全组。' 'Adds inbound TCP allows to active UFW/firewalld only; SSH and default policies stay unchanged. Also check provider security groups.'
 if [[ -n $value ]]; then
  confirm "放行 TCP ${value}？" "Allow TCP $value?" || return 0
 else
  helper node-ports || return 1
  confirm '放行以上全部已安装节点的 TCP 端口？' 'Allow TCP ports for all installed nodes above?' || return 0
 fi
 if ! helper firewall-allow ${flags[@]+"${flags[@]}"}; then
  error '防火墙操作未完成，部分放行规则可能已添加；请查看状态后重试。' 'Firewall operation incomplete; some allows may have been added. Check status before retrying.'
  return 1
 fi
 say 'TCP 放行命令已完成；仍需验证区域、IPv6 规则、规则优先级及公网连接。' 'TCP allow commands completed; still verify zone, IPv6 rules, rule priority and public connectivity.'
}
install_firewall(){
 local detected='' ssh_input extra_input
 local ssh_ports=() extra_ports=() flags=()
 helper firewall-setup-check || return 1
 if [[ -n ${SSH_CONNECTION:-} ]]; then detected=${SSH_CONNECTION##* }; fi
 if [[ -n $detected ]]; then
  ssh_input=$(ask "SSH TCP 端口（可空格分隔）[$detected]：" "SSH TCP ports (space-separated) [$detected]: ") || return 1
  ssh_input=${ssh_input:-$detected}
 else
  ssh_input=$(ask 'SSH TCP 端口（必填，可空格分隔，不默认使用 22）：' 'SSH TCP ports (required, space-separated; no assumed port 22): ') || return 1
 fi
 read -r -a ssh_ports <<< "$ssh_input"
 (( ${#ssh_ports[@]} )) || { error '必须填写 SSH 端口。' 'SSH ports are required.'; return 1; }
 extra_input=$(ask '其他需保留的 TCP 端口（空格分隔，例如 80 443；回车无；节点端口自动添加）：' 'Other TCP ports to retain (e.g. 80 443; Enter for none; node ports are automatic): ') || return 1
 read -r -a extra_ports <<< "$extra_input"
 flags+=(--ssh-ports "${ssh_ports[@]}")
 (( ${#extra_ports[@]} == 0 )) || flags+=(--ports "${extra_ports[@]}")
 helper firewall-setup-plan "${flags[@]}" || return 1
 warn '将通过系统 APT 安装 UFW（如缺少），先放行上述 TCP 端口，再启用默认拒绝入站、允许出站。其他未放行服务可能受影响；请确认 SSH 端口并保留服务商控制台入口。服务商安全组仍需单独设置。' 'Installs UFW with APT if missing, allows the TCP ports above, then enables deny-incoming/allow-outgoing defaults. Other services may be blocked; verify SSH ports and keep provider console access available. Provider security groups remain separate.'
 confirm '安装并启用 UFW？' 'Install and enable UFW?' || return 0
 if ! command -v ufw >/dev/null; then
  apt_refresh && apt-get install -y ufw || return 1
 fi
 helper firewall-setup "${flags[@]}" || return 1
 say 'UFW 已启用；请在保留当前 SSH 会话时，新开一个 SSH 连接验证访问。' 'UFW enabled; keep this SSH session and verify access from a new SSH connection.'
 report_output helper firewall-status
}
remove_firewall(){
 local choice current=absent plan='' result action=--remove
 menu '仅操作 UFW：\n1 仅停用，保留软件包和规则配置\n2 卸载软件包，保留规则配置\n3 卸载并清除规则配置\n0 返回' 'UFW only:\n1 Disable only; keep package and rule configuration\n2 Remove package; keep rule configuration\n3 Remove package and purge rule configuration\n0 Back'
 choice=$(ask '> ' '> ') || return 1
 case $choice in 0) return 0;; 1|2|3) :;; *) return 1;; esac
 if [[ $choice != 1 ]]; then
  if [[ $choice == 3 ]]; then
   action=--purge
   plan=$(helper ufw-remove-plan --purge) || return 1
  else
   plan=$(helper ufw-remove-plan) || return 1
  fi
  if [[ $plan == absent ]]; then
   if [[ $choice == 3 ]]; then
    say 'dpkg 未记录 UFW 软件包或残留配置；未清理未知文件。' 'dpkg records no UFW package or residual configuration; unknown files were not deleted.'
   else
    say 'UFW 软件包未安装，无需卸载；残留配置保持原样。' 'UFW package is not installed; nothing to remove. Any residual configuration is retained.'
   fi
   return 0
  fi
  if [[ $plan != ready && ( $plan != config-files || $choice != 3 ) ]]; then
   error '无法确认 UFW 卸载计划，未执行操作。' 'UFW removal plan was not recognized; no action taken.'
   return 1
  fi
 fi
 if [[ $plan == config-files ]]; then
  say 'UFW 软件包已卸载，仅剩规则配置。' 'UFW package is already removed; only configuration remains.'
 else
  current=$(helper ufw-state) || return 1
  say "当前 UFW 状态：$current" "Current UFW state: $current"
  if [[ $choice == 1 && $current == absent ]]; then
   say '未找到 UFW，无需停用。' 'UFW was not found; nothing to disable.'
   return 0
  fi
  warn '停用后 UFW 的主机入站保护将不再生效，原先被阻止的端口可能可达。此操作仅针对 UFW；其他防火墙和服务商安全组仍各自生效。节点、SSH 配置和 BBR 参数保留。' 'Disabling UFW removes its host filtering protection; previously blocked ports may become reachable. Only UFW is targeted; other firewalls and provider rules remain separate. Node, SSH configuration and BBR settings are retained.'
 fi
 if [[ $choice == 3 ]]; then
  warn '将通过 dpkg 清除 UFW 软件包及规则配置，此操作不可恢复；如需保留，请选择第 2 项。其他软件及未知文件不在清理范围内。' 'dpkg will purge the UFW package and rule configuration. This cannot be undone; choose option 2 to retain configuration. Other software and unknown files are outside the cleanup scope.'
  confirm '卸载 UFW 并清除规则配置？' 'Remove UFW and purge its rule configuration?' || return 0
 elif [[ $choice == 2 ]]; then
  confirm '先停用并验证 UFW，再卸载 UFW 软件包（保留配置）？' 'Disable and verify UFW, then remove its package while keeping configuration?' || return 0
 else
  confirm '停用 UFW（保留软件包和配置）？' 'Disable UFW while keeping its package and configuration?' || return 0
 fi
 if [[ $plan != config-files ]]; then
  result=$(helper ufw-disable) || return 1
  if [[ $result != disabled ]]; then
   error '没有确认 UFW 停用成功，未继续卸载。' 'UFW disable was not confirmed; package removal was not attempted.'
   return 1
  fi
 fi
 if [[ $choice == 1 ]]; then
  say 'UFW 已停用，软件包和规则配置保留。' 'UFW disabled; its package and rule configuration are retained.'
  return 0
 fi
 # Target only ufw, with purge selected explicitly; never force dependencies or autoremove.
 if ! dpkg "$action" ufw; then
  if [[ $choice == 3 ]]; then
   error 'UFW 软件包或规则配置清除未完成，可能已部分清除；请检查上方 dpkg 提示。不会自动重新启用。' 'UFW package or configuration purge did not complete; some files may already be removed. Inspect the dpkg output above. It will not be re-enabled automatically.'
  else
   error 'UFW 已停用，但软件包卸载未完成；请检查上方 dpkg 提示。不会自动重新启用。' 'UFW is disabled, but package removal did not complete; inspect the dpkg output above. It will not be re-enabled automatically.'
  fi
  return 1
 fi
 result=$(helper ufw-package-state) || return 1
 if [[ $choice == 3 && $result == absent ]]; then
  say 'UFW 软件包及规则配置已由 dpkg 清除；未清理其他软件或未知文件。' 'UFW package and rule configuration purged by dpkg; other software and unknown files were not deleted.'
 elif [[ $choice == 2 && ( $result == absent || $result == config-files ) ]]; then
  say 'UFW 软件包已卸载，规则配置保留。未卸载 iptables/nftables 或其他防火墙，也未执行全局规则清空。' 'UFW package removed; rule configuration retained. iptables/nftables and other firewalls were not removed, and no global rule flush was performed.'
 else
  error '尚未确认 UFW 软件包卸载或配置清除完成；请检查软件包状态。' 'UFW package removal or configuration purge could not be verified; check package status.'
  return 1
 fi
}
network_menu(){
 local choice value
 # --menu renders only; a numeric argument executes one selected operation.
 if [[ $# == 0 || $1 == --menu ]]; then
 menu '防火墙\n1 查看防火墙状态\n2 安装并启用 UFW\n3 放行全部节点 TCP 端口\n4 放行指定 TCP 端口\n5 停用/卸载 UFW\n\nBBR\n6 查看 BBR 状态\n7 启用 BBR + fq\n8 恢复启用前参数\n\nIPv6 备用入口\n9 IPv6 状态 / 启用 / 移除备用入口\n\n0 返回' 'Firewall\n1 Show firewall status\n2 Install and enable UFW\n3 Allow all node TCP ports\n4 Allow a TCP port\n5 Disable/remove UFW\n\nBBR\n6 Show BBR status\n7 Enable BBR + fq\n8 Restore previous settings\n\nIPv6 backup entry\n9 IPv6 status / enable / remove backup entry\n\n0 Back'
 [[ ${1:-} != --menu ]] || return 0
 choice=$(ask '> ' '> ') || return 1
 else
  choice=$1
 fi
 case $choice in
  1) report_output helper firewall-status;;
  2) install_firewall;;
  3) firewall_open;;
  4) value=$(ask '要放行的 TCP 端口（1–65535）：' 'TCP port to allow (1–65535): ') || return 1
     if [[ ! $value =~ ^[0-9]{1,5}$ ]] || (( 10#$value < 1 || 10#$value > 65535 )); then
      error 'TCP 端口无效。' 'Invalid TCP port.'; return 1
     fi
     firewall_open "$value";;
  5) remove_firewall;;
  6) report_output helper bbr-status;;
  7) warn 'BBR 调整全系统新 TCP 连接的默认拥塞控制；不保证提速，不更换内核或重启服务，也不替换现有网卡队列。' 'BBR changes the system default for new TCP connections; speed gains vary. No kernel replacement, service restart or live interface queue replacement.'
     confirm '保存原参数并启用 BBR + fq？' 'Save previous values and enable BBR + fq?' || return 0
     helper bbr-enable || return 1
     report_output helper bbr-status;;
  8) confirm '恢复本脚本启用 BBR 前的系统参数并移除本脚本的持久化文件？' 'Restore values saved before enabling BBR and remove the managed persistence file?' || return 0
     helper bbr-restore || return 1
     report_output helper bbr-status;;
  0) return 0;; *) return 1;;
 esac
}
