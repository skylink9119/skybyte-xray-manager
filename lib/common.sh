# lib/common.sh — build-time module; assembled by scripts/build.py.
say(){ if [[ $LANGUAGE == en ]]; then printf '%s\n' "$2"; else printf '%s\n' "$1"; fi; }
menu(){ printf '%s' "$GREEN"; if [[ $LANGUAGE == en ]]; then printf '%b\n' "$2"; else printf '%b\n' "$1"; fi; printf '%s' "$RESET"; }
warn(){ printf '%s' "$YELLOW"; say "$1" "$2"; printf '%s' "$RESET"; }
error(){ printf '%s' "$RED" >&2; say "$1" "$2" >&2; printf '%s' "$RESET" >&2; }
ask(){
 local result
 printf '%s' "$GREEN" >&2
 if [[ $LANGUAGE == en ]]; then printf '%s' "$2" >&2; else printf '%s' "$1" >&2; fi
 printf '%s' "$RESET" >&2
 IFS= read -r result || return 1
 printf '%s' "$result"
}
confirmed(){ [[ $1 =~ ^[[:space:]]*[Yy][[:space:]]*$ ]]; }
confirm(){ local answer; answer=$(ask "$1 [y/N]：" "$2 [y/N]: ") || return 1; confirmed "$answer"; }
# Keep report commands attached to the terminal (vnStat live mode needs a TTY).
report_output(){
 local report_status=0 report_reset=$RESET
 if [[ ! -t 1 || -n ${NO_COLOR:-} ]];then "$@";return $?;fi
 printf '%s' "$YELLOW"
 local GREEN=$YELLOW RED=$YELLOW CYAN=$YELLOW RESET=$YELLOW
 (
  export NO_COLOR=1 SYSTEMD_COLORS=0 CLICOLOR=0
  "$@"
 ) || report_status=$?
 printf '%s' "$report_reset"
 return "$report_status"
}
separator(){ printf '%s\n' '------------------------------------------------------------'; }
acquire_lock(){
 [[ ! -L $SKYBYTE_XRAY_LOCK && ( ! -e $SKYBYTE_XRAY_LOCK || -f $SKYBYTE_XRAY_LOCK ) ]] || return 1
 exec 9>"$SKYBYTE_XRAY_LOCK"
 flock -n 9 || { error '已有管理任务正在运行。' 'Another management task is running.'; return 1; }
}
choose_language(){
 local result
 menu '=========== Language / 语言 ===========\n1. 简体中文\n2. English' '=========== Language / 语言 ===========\n1. 简体中文\n2. English'
 result=$(ask '> ' '> ') || return 1
 case $result in 1) LANGUAGE=zh;; 2) LANGUAGE=en;; *) return 1;; esac
 if [[ -f $SKYBYTE_XRAY_DIR/.owner ]]; then
  helper guard || return 1
  [[ ! -L $SKYBYTE_XRAY_DIR/language ]] || return 1
  printf '%s\n' "$LANGUAGE" > "$SKYBYTE_XRAY_DIR/language"
 fi
}
load_language(){
 local stored=''
 if [[ -f $SKYBYTE_XRAY_DIR/language && ! -L $SKYBYTE_XRAY_DIR/language ]]; then
  IFS= read -r stored < "$SKYBYTE_XRAY_DIR/language" || true
 fi
 case $stored in zh|en) LANGUAGE=$stored;; *) choose_language;; esac
}
lib_guard(){
 python3 - "$SKYBYTE_XRAY_LIB" "$SKYBYTE_XRAY_BINARY" <<'PY'
import os,sys
from pathlib import Path
p,binary=map(Path,sys.argv[1:])
for item in (p,binary,*p.parents):
 if item.is_symlink(): raise SystemExit('Unsafe binary path / 核心路径异常')
if not p.is_absolute() or binary.parent != p or binary.name != 'xray': raise SystemExit('Invalid binary directory')
marker=p/'.owner'
if marker.is_symlink(): raise SystemExit('Unsafe owner marker')
if p.exists() and (not p.is_dir() or not marker.is_file() or marker.read_text()!='SKYBYTE-XRAY/1\n'):
 raise SystemExit('Existing directory not owned / 拒绝覆盖已有核心目录')
p.mkdir(parents=True,exist_ok=True,mode=0o700)
os.chmod(p,0o700)
if not marker.exists(): marker.write_text('SKYBYTE-XRAY/1\n');os.chmod(marker,0o600)
PY
}
