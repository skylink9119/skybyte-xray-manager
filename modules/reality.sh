# modules/reality.sh — build-time module; assembled by scripts/build.py.
choose_reality_sni(){
 local choice selected
 menu 'Reality 握手域名\n1 Microsoft  www.microsoft.com（默认）\n2 Apple      www.apple.com\n3 Amazon     www.amazon.com\n4 Cloudflare www.cloudflare.com\n5 Google     dl.google.com\n6 自定义域名\n0 返回' 'Reality handshake name\n1 Microsoft  www.microsoft.com (default)\n2 Apple      www.apple.com\n3 Amazon     www.amazon.com\n4 Cloudflare www.cloudflare.com\n5 Google     dl.google.com\n6 Custom domain\n0 Back' >&2
 while :; do
  choice=$(ask '选择 [1]（也可直接输入域名）：' 'Choose [1] (or enter a domain directly): ') || return 1
  case ${choice:-1} in
   1) selected=www.microsoft.com;;
   2) selected=www.apple.com;;
   3) selected=www.amazon.com;;
   4) selected=www.cloudflare.com;;
   5) selected=dl.google.com;;
   6) while :; do
       selected=$(ask '自定义 Reality 握手域名（必填）：' 'Custom Reality handshake domain (required): ') || return 1
       [[ $selected =~ [^[:space:]] ]] && break
       warn '请填写握手域名。' 'Enter a handshake domain.' >&2
      done;;
   0) return 0;;
   *) if [[ $choice =~ ^[0-9]+$ ]]; then
       warn '选项无效，请输入 1–6、0 或域名。' 'Invalid option; enter 1–6, 0 or a domain.' >&2
       continue
      fi
      selected=$choice;;
  esac
  printf '%s\n' "$selected"
  return 0
 done
}
reality_engine(){ python3 - "$@" <<'PY_REALITY'
# BUILD_REALITY
PY_REALITY
}
reality_replace(){
 local current choice kind available=no item _old_target _old_sni sni target stage
 current=$(helper reality-targets) || return 1
 [[ -n $current ]] || { warn '未安装 Reality 节点，无需更换；可选择检测自定义网站。' 'No Reality node installed; use a custom target check instead.';return 0; }
 say '当前节点 / 握手目标 / SNI：' 'Current node / target / SNI:'
 printf '%s\n' "$current"
 menu '选择要更换的节点\n1. Reality + Vision\n2. XHTTP + Reality\n0. 返回' 'Select the node to update\n1. Reality + Vision\n2. XHTTP + Reality\n0. Back'
 choice=$(ask '> ' '> ') || return 0
 case $choice in 1) kind=vision;;2) kind=xhttp-reality;;0) return 0;;*) return 1;;esac
 while IFS=$'\t' read -r item _old_target _old_sni;do
  [[ $item != "$kind" ]] || available=yes
 done <<< "$current"
 [[ $available == yes ]] || { error '所选 Reality 节点尚未安装，保留原配置。' 'Selected Reality node is not installed; configuration retained.';return 1; }
 sni=$(choose_reality_sni) || return 0
 [[ -n $sni ]] || return 0
 target=$(ask "握手目标 [$sni:443]（0 返回）：" "Handshake target [$sni:443] (0 to return): ") || return 0
 [[ $target != 0 ]] || return 0
 target=${target:-$sni:443}
 helper reality-edit --kind "$kind" --sni "$sni" --target "$target" --check-only || return 1
 if ! report_output reality_engine --project xray --language "$LANGUAGE" --target "$target" --sni "$sni";then
  error '新目标检测未通过，保留原配置。' 'New target failed checks; original configuration retained.';return 1
 fi
 warn '更换会短暂重启正在运行的服务；保留 UUID、密钥、端口及路径。所选节点的客户端需重新导入更新后的配置。' 'Running services will briefly restart; UUID, keys, port and path are retained. Re-import updated configuration on clients of this node.'
 confirm '将所选节点的 Reality 握手网站更换为上述目标？' 'Apply this Reality handshake target to the selected node?' || return 0
 stage=$(helper reality-edit --kind "$kind" --sni "$sni" --target "$target") || return 1
 apply_stage "$stage" || return 1
 say 'Reality 握手网站已更换；请重新导入节点或更新客户端 SNI。' 'Reality target updated; re-import the node or update client SNI.'
}
reality_menu(){
 local choice target sni
 if [[ $# == 0 || $1 == --menu ]]; then
  menu 'Reality 握手网站检测\n1. 检测当前节点的握手网站\n2. 检测自定义网站\n3. 更换握手网站（先检测后应用）\n0. 返回' 'Reality handshake target checks\n1. Check configured Reality targets\n2. Check a custom target\n3. Change handshake target (check before applying)\n0. Back'
  [[ ${1:-} != --menu ]] || return 0
  choice=$(ask '> ' '> ') || return 0
 else choice=$1; fi
 case $choice in
  1) report_output reality_engine --project xray --language "$LANGUAGE" --config "$SKYBYTE_XRAY_DIR/config.json";;
  2) target=$(ask '握手目标（域名或 域名:端口，0 返回）：' 'Target (hostname or host:port, 0 to return): ') || return 0
     [[ $target != 0 ]] || return 0
     [[ -n $target ]] || { error '请填写握手目标。' 'Enter a target.';return 1; }
     sni=$(ask '握手域名 / SNI（回车使用目标域名）：' 'Handshake SNI (Enter uses target hostname): ') || return 0
     report_output reality_engine --project xray --language "$LANGUAGE" --target "$target" --sni "$sni";;
  3) reality_replace;;
  0) return 0;; *) return 1;;
 esac
}
