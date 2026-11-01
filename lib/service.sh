# lib/service.sh — build-time module; assembled by scripts/build.py.
core_asset(){
 case $(uname -m) in x86_64|amd64) printf 'Xray-linux-64.zip';; aarch64|arm64) printf 'Xray-linux-arm64-v8a.zip';;
 *) error '首版支持 amd64 / arm64。' 'This version supports amd64 / arm64.'; return 1;; esac
}
ensure_binary(){
 helper guard && lib_guard || return 1
 if [[ ! -x $SKYBYTE_XRAY_BINARY ]]; then
  local candidate asset
  asset=$(core_asset) || return 1
  candidate=$(mktemp "$SKYBYTE_XRAY_LIB/.download.XXXXXX") || return 1
  say '正在下载并校验官方 Xray 核心……' 'Downloading and verifying official Xray-core…'
  if ! helper download --file "$candidate" --asset "$asset" --tag "$CORE_VERSION"; then rm -f -- "$candidate"; return 1; fi
  if ! "$candidate" version >/dev/null; then rm -f -- "$candidate"; return 1; fi
  mv -f -- "$candidate" "$SKYBYTE_XRAY_BINARY" || return 1
 fi
 [[ ! -L $SKYBYTE_XRAY_DIR/language ]] || return 1
 printf '%s\n' "$LANGUAGE" > "$SKYBYTE_XRAY_DIR/language"
}
restore_service(){
 local active=$1 enabled=$2
 systemctl daemon-reload || return 1
 if [[ $enabled == yes ]]; then systemctl enable skybyte-xray.service >/dev/null 2>&1 || return 1
 else systemctl disable skybyte-xray.service >/dev/null 2>&1 || true; fi
 if [[ $active == yes ]]; then systemctl restart skybyte-xray.service || return 1
 else systemctl stop skybyte-xray.service >/dev/null 2>&1 || true; fi
}
recover(){
 if [[ -d $SKYBYTE_XRAY_DIR/.transaction ]]; then
  local flags active enabled
  warn '恢复未完成的配置事务。' 'Recovering an interrupted configuration transaction.'
  flags=$(helper journal | python3 -c 'import json,sys;x=json.load(sys.stdin);print("yes" if x["active"] else "no", "yes" if x["enabled"] else "no")') || return 1
  read -r active enabled <<< "$flags"
  helper rollback >/dev/null && restore_service "$active" "$enabled" || return 1
 fi
 if [[ -f $SKYBYTE_XRAY_LIB/.old-core ]]; then
  lib_guard || return 1
  [[ ! -L $SKYBYTE_XRAY_LIB/.old-core && ! -L $SKYBYTE_XRAY_LIB/.update-active ]] || return 1
  local previous=no
  if [[ -f $SKYBYTE_XRAY_LIB/.update-active ]]; then IFS= read -r previous < "$SKYBYTE_XRAY_LIB/.update-active" || true; fi
  mv -f -- "$SKYBYTE_XRAY_LIB/.old-core" "$SKYBYTE_XRAY_BINARY" || return 1
  rm -f -- "$SKYBYTE_XRAY_LIB/.update-active"
  [[ $previous != yes ]] || systemctl restart skybyte-xray.service || return 1
 fi
}
apply_stage() (
 local stage=$1 activate=${2:-no} readiness=${3:-no} was_active=no was_enabled=no applied=0 accepted=0
 local flags=(--stage "$stage")
 systemctl is-active --quiet skybyte-xray.service && was_active=yes
 systemctl is-enabled --quiet skybyte-xray.service && was_enabled=yes
 [[ $was_active != yes ]] || flags+=(--active)
 [[ $was_enabled != yes ]] || flags+=(--enabled)
 # shellcheck disable=SC2317,SC2329 # EXIT trap invocation is indirect; rollback tests exercise this function.
 cleanup_stage(){
  local status=$?
  if (( applied && ! accepted )); then
   if helper rollback >/dev/null; then restore_service "$was_active" "$was_enabled" || true
   else error '回退失败，已保留恢复事务，请勿手动删除。' 'Rollback failed; recovery journal retained.'; fi
  fi
  if [[ $stage == "$SKYBYTE_XRAY_DIR"/.stage-* && -d $stage && ! -L $stage ]]; then rm -rf -- "$stage"; fi
  return "$status"
 }
 trap cleanup_stage EXIT
 helper commit "${flags[@]}" || return 1
 applied=1
 systemctl daemon-reload || return 1
 local node_count
 node_count=$(python3 - "$SKYBYTE_XRAY_DIR/state.json" <<'PY'
import json,sys
with open(sys.argv[1]) as f: print(len(json.load(f)['nodes']))
PY
) || return 1
 if [[ $node_count == 0 ]]; then
  systemctl stop skybyte-xray.service && systemctl disable skybyte-xray.service >/dev/null 2>&1 || return 1
 elif [[ $activate == yes ]]; then
  systemctl enable skybyte-xray.service >/dev/null 2>&1 && systemctl restart skybyte-xray.service || return 1
 elif [[ $was_active == yes ]]; then systemctl restart skybyte-xray.service || return 1; fi
 if [[ $node_count != 0 && ( $activate == yes || $was_active == yes ) ]]; then
  local attempt running=0
  for ((attempt=0; attempt<5; attempt++)); do
   sleep 1
   if systemctl is-active --quiet skybyte-xray.service; then running=1; break; fi
  done
  (( running )) || return 1
  case $readiness in
   ipv6) ipv6_engine ready || return 1;;
   ipv6-install:*) ipv6_engine ready-install "${readiness#*:}" || return 1;;
  esac
 fi
 helper finalize --stage "$stage" || return 1
 accepted=1
)
configuration_check(){
 if [[ ! -f $SKYBYTE_XRAY_DIR/config.json ]];then
  error '[未检查] 未发现节点配置，请先安装节点。' '[Not checked] No node configuration found; install a node first.'
  return 1
 fi
 if [[ ! -x $SKYBYTE_XRAY_BINARY ]];then
  error '[未检查] Xray 核心不存在或不可执行。' '[Not checked] Xray binary is missing or not executable.'
  return 1
 fi
 say '===== Xray 配置检查 =====' '===== Xray configuration check ====='
 say "配置文件：$SKYBYTE_XRAY_DIR/config.json" "Configuration file: $SKYBYTE_XRAY_DIR/config.json"
 if "$SKYBYTE_XRAY_BINARY" run -test -config "$SKYBYTE_XRAY_DIR/config.json";then
  say '[通过] 配置检查通过' '[PASS] Configuration check passed'
  say '检查范围：配置有效性，不代表服务已运行或公网已连通。' 'Scope: configuration validity; service status and public connectivity are not tested.'
 else
  error '[失败] 配置检查未通过，请查看上方核心报错。' '[FAIL] Configuration check failed; see the core error above.'
  return 1
 fi
}
service_menu(){
 helper guard || return 1
 # --menu renders only; a numeric argument executes one selected operation.
 if [[ $# == 0 || $1 == --menu ]]; then
 menu '1. 状态
2. 启动
3. 停止
4. 重启
5. 配置检查
6. 日志
0. 返回' '1. Status
2. Start
3. Stop
4. Restart
5. Validate
6. Logs
0. Back'
 local choice
 [[ ${1:-} != --menu ]] || return 0
 choice=$(ask '> ' '> ') || return 1
 else
  choice=$1
 fi
 case $choice in
  1) report_output systemctl status skybyte-xray.service --no-pager || true;;
  2) systemctl start skybyte-xray.service;; 3) systemctl stop skybyte-xray.service;; 4) systemctl restart skybyte-xray.service;;
  5) report_output configuration_check;;
  6) report_output journalctl -u skybyte-xray.service -n 60 --no-pager;; 0) return 0;; *) return 1;;
 esac
}
update_core() (
 ensure_binary || return 1
 local tag candidate asset active=no accepted=0 replaced=0
 tag=$(ask "官方稳定版本 [$CORE_VERSION]：" "Official stable version [$CORE_VERSION]: ") || return 1; tag=${tag:-$CORE_VERSION}
 confirm '校验并更新核心？运行中的节点会短暂重启。' 'Verify and update core? Active nodes will briefly restart.' || return 1
 [[ ! -e $SKYBYTE_XRAY_LIB/.old-core && ! -e $SKYBYTE_XRAY_LIB/.update-active ]] || return 1
 candidate=$(mktemp "$SKYBYTE_XRAY_LIB/.update.XXXXXX") || return 1
 # shellcheck disable=SC2317,SC2329 # EXIT trap invocation is indirect; rollback tests exercise this function.
 update_cleanup(){
  local status=$?
  if (( ! accepted && replaced )); then
   mv -f -- "$SKYBYTE_XRAY_LIB/.old-core" "$SKYBYTE_XRAY_BINARY" || return 1
   [[ $active != yes ]] || systemctl restart skybyte-xray.service || true
  fi
  rm -f -- "$candidate"
  [[ -e $SKYBYTE_XRAY_LIB/.old-core ]] || rm -f -- "$SKYBYTE_XRAY_LIB/.update-active"
  return "$status"
 }
 trap update_cleanup EXIT
 asset=$(core_asset) || return 1
 helper download --asset "$asset" --tag "$tag" --file "$candidate" || return 1
 [[ ! -f $SKYBYTE_XRAY_DIR/config.json ]] || "$candidate" run -test -config "$SKYBYTE_XRAY_DIR/config.json" >/dev/null 2>&1 || return 1
 systemctl is-active --quiet skybyte-xray.service && active=yes
 cp -p -- "$SKYBYTE_XRAY_BINARY" "$SKYBYTE_XRAY_LIB/.old-core" || return 1
 printf '%s\n' "$active" > "$SKYBYTE_XRAY_LIB/.update-active"
 mv -f -- "$candidate" "$SKYBYTE_XRAY_BINARY" || return 1
 replaced=1
 if [[ $active == yes ]]; then
  systemctl restart skybyte-xray.service || return 1
  sleep 2
  systemctl is-active --quiet skybyte-xray.service || return 1
 fi
 rm -f -- "$SKYBYTE_XRAY_LIB/.old-core" "$SKYBYTE_XRAY_LIB/.update-active"
 accepted=1
)
update_manager(){
 local tag
 say "当前管理脚本：v${VERSION}，正在检查最新正式版……" "Current manager: v$VERSION; checking the latest stable release…"
 tag=$(helper manager-latest) || return 1
 if [[ -z $tag ]]; then
  say '当前版本已不低于最新正式版。' 'The current version is at least as new as the latest stable release.'
  return 2
 fi
 say "可更新到：$tag" "Available update: $tag"
 confirm '校验并更新管理脚本？节点和核心保持原样，成功后请重新运行 xr。' 'Verify and update the manager? Nodes and core are retained; reopen with xr after success.' || return 2
 if ! helper manager-update --release "$tag" --file "$SKYBYTE_XRAY_LIB/manager.sh"; then
  error '管理脚本更新未完成，请检查上方原因；已有备份位于 manager.previous.sh。' 'Manager update did not complete; check the reason above. Any saved backup is manager.previous.sh.'
  return 1
 fi
 say '管理脚本已更新，旧脚本保存为 manager.previous.sh。请重新输入 xr。' 'Manager updated; the old script is saved as manager.previous.sh. Run xr again.'
}
