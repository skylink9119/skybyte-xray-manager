# lib/menu.sh — build-time module; assembled by scripts/build.py.
run_submenu(){
 local handler=$1 choice
 while :; do
  "$handler" --menu || { error '无法打开此菜单，请检查上方提示。' 'Cannot open this menu; inspect the output above.';return 0; }
  say '操作后留在此菜单；0 返回上一层。' 'Stay in this menu after each operation; 0 returns one level.'
  choice=$(ask '> ' '> ') || return 0
  [[ $choice != 0 ]] || return 0
  if [[ $handler == network_menu && $choice == 9 ]];then run_submenu ipv6_menu;continue;fi
  if [[ $handler == warp_menu && $choice == 6 ]];then run_submenu media_check;continue;fi
  if ! ( "$handler" "$choice" ); then
   error '操作未完成或已取消；可在当前菜单继续选择。' 'Operation incomplete or cancelled; choose again in this menu.'
  fi
 done
}
main_menu(){
 while :; do
  show_banner
  show_startup_info
  printf '%sYouTube: https://www.youtube.com/@SKYBYTE9119%s\n' "$CYAN" "$RESET"
  say '觉得脚本好用，欢迎订阅我的 YouTube 频道，支持后续维护。' 'If this script helps, subscribe to my YouTube channel to support maintenance.'
  menu '【节点】
a. 安装 / 添加节点
b. 查看节点与客户端配置
c. 节点二维码
e. 编辑节点 / 删除 / TLS 证书
p. 查看节点参数（注意保密）

【服务与网络】
d. 服务与日志
l. 防火墙 / BBR / IPv6 备用
n. WARP 分流 / 平台检测
o. Reality 握手网站检测

【更新与备份】
f. 更新 Xray 核心
m. 更新管理脚本
g. 备份配置
h. 恢复配置

【设置】
i. 使用说明
j. 切换语言
k. 卸载

q. 退出' '[Nodes]
a. Install / add nodes
b. Nodes and client configs
c. Node QR codes
e. Edit nodes / remove / TLS certificate
p. View node parameters (keep private)

[Services and network]
d. Service and logs
l. Firewall / BBR / IPv6 backup
n. WARP routing / platform tests
o. Reality handshake target checks

[Updates and backups]
f. Update Xray-core
m. Update manager script
g. Back up configuration
h. Restore configuration

[Settings]
i. Guide
j. Language
k. Uninstall

q. Exit'
  local choice
  choice=$(ask '请选择（字母）：' 'Choose (letter): ') || return 0
  # Read-only views reuse a brief in-memory snapshot; management actions refresh it.
  case $choice in a|A|1|d|D|4|e|E|5|f|F|6|h|H|8|j|J|10|k|K|11|l|L|12|m|M|13|n|N|14|o|O|15) OVERVIEW_CACHE_AT=-10;; esac
  case $choice in
   a|A|1) install_node standard || error '操作未完成或已取消；失败原因见上方提示。' 'Operation did not complete or was cancelled; see the reason above.';;
   b|B|2) show_nodes || error '无法读取节点，配置和导出文件未修改；请检查上方提示。' 'Cannot read nodes; configuration and exports are unchanged. Inspect the output above.';; c|C|3) qr_nodes || true;; d|D|4) run_submenu service_menu;; e|E|5) run_submenu edit_nodes;;
   f|F|6) update_core || error '核心更新失败，已保留或回退原核心。' 'Core update failed; previous core retained or restored.';;
   g|G|7) make_backup || true;; h|H|8) restore_backup || error '恢复失败，原配置已保留或回退。' 'Restore failed; previous configuration retained or restored.';;
   i|I|9) guide;; j|J|10) choose_language || true;; k|K|11) uninstall || error '卸载未完成。' 'Uninstall did not complete.';;
   l|L|12) run_submenu network_menu;;
   m|M|13) if update_manager; then return 0; fi;; q|Q|0) return 0;;
   n|N|14) run_submenu warp_menu;;
   o|O|15) run_submenu reality_menu;;
   p|P|16) show_parameters || error '无法读取节点参数，请检查本机托管配置。' 'Cannot read node parameters; inspect local managed configuration.';;
   *) warn '选项无效。' 'Invalid option.';;
  esac
 done
}
main(){
 case ${1:-} in --version) printf 'SKYBYTE Xray Manager %s\n' "$VERSION"; return 0;; --self-check) helper selfcheck; return;;
 --help) printf 'bash xray-manager.sh [--version|--self-check|--help]\n'; return;; '') :;; *) return 1;; esac
 environment_check && dependencies && acquire_lock || return 1
 recover && load_language && main_menu
}
if [[ ${BASH_SOURCE[0]} == "$0" ]]; then main "$@"; fi
