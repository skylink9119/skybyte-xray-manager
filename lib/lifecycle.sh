# lib/lifecycle.sh — build-time module; assembled by scripts/build.py.
uninstall(){
 helper guard && lib_guard || return 1
 confirm '备份后卸载 SKYBYTE Xray Manager？' 'Back up and uninstall SKYBYTE Xray Manager?' || return 1
 make_backup || return 1
 if [[ -f $SKYBYTE_XRAY_UNIT ]]; then
  systemctl stop skybyte-xray.service && systemctl disable skybyte-xray.service || return 1
 fi
 python3 - "$SKYBYTE_XRAY_DIR" "$SKYBYTE_XRAY_UNIT" "$SKYBYTE_XRAY_LIB" "$SKYBYTE_XRAY_SHORTCUT" <<'PY'
import json,sys
from pathlib import Path
root,unit,lib,shortcut=map(Path,sys.argv[1:])
state_file=root/'state.json'
state=json.loads(state_file.read_text()) if state_file.exists() else {'nodes':{}}
paths=[root/x for x in ['state.json','config.json','nodes.txt','subscription-base64.txt','language']] if state_file.exists() else []
for kind,node in state['nodes'].items():
 paths.append(root/('client-'+kind+'.json'))
 if 'ipv6_backup' in node:paths.append(root/('client-'+kind+'-ipv6.json'))
 if kind=='xhttp-tls': paths.extend([root/node['cert'],root/node['key']])
paths.extend([unit,lib/'xray'])
if any(p.is_symlink() or (p.exists() and not p.is_file()) for p in paths): raise SystemExit('Unsafe managed file')
if unit.exists() and not unit.read_text().startswith('# SKYBYTE Xray Manager unit v1\n'): raise SystemExit('Unknown service')
manager=lib/'manager.sh'
if manager.exists():
 if manager.is_symlink() or not manager.read_text().startswith('#!/usr/bin/env bash\n# SKYBYTE Xray Manager standalone;'): raise SystemExit('Unknown manager')
 paths.append(manager)
if shortcut.is_file() and not shortcut.is_symlink():
 if shortcut.read_text().startswith('#!/usr/bin/env bash\n# SKYBYTE Xray Manager shortcut v1\n') and str(manager) in shortcut.read_text():
  paths.append(shortcut)
for p in paths:
 if p.exists(): p.unlink()
PY
 systemctl daemon-reload || return 1
 warn '已卸载。备份、未知文件、系统依赖、防火墙规则和 BBR 设置保留；如需恢复 BBR，请在卸载前使用菜单 l → 8。' 'Removed. Backups, unknown files, dependencies, firewall rules and BBR settings retained; restore BBR with menu l → 8 before uninstalling if needed.'
 exit 0
}
