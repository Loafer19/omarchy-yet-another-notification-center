# shellcheck shell=bash
# Following Omarchy: sync once, then archive what inotify reports.
# Sourced by backend.sh.

quiet=0
engine=legacy

sync_and_prune() {
  local sync=sync_all
  [[ $engine == omapager ]] && sync=ingest_engine
  if (( quiet )); then "$sync" >/dev/null; else "$sync"; fi
  prune || return 1
  [[ $engine == omapager ]] && prune_captures
  return 0
}

cmd_sync() {
  ensure_store
  with_lock sync_and_prune
}

# legacy | omapager | auto (omapager when its files are there). The panel
# passes what the running Omarchy service is; auto is its fallback.
set_engine() {
  case ${1:-legacy} in
    legacy|"") engine=legacy ;;
    omapager) engine=omapager ;;
    auto) if engine_files_present; then engine=omapager; else engine=legacy; fi ;;
    *) die "unknown engine: $1" ;;
  esac
}

ingest_one() {
  ingest_file "$1" 1
  prune
}

ingest_engine_one() {
  ingest_engine
  prune
}

cmd_watch() {
  set_engine "${1:-legacy}"
  ensure_store
  local -a dirs
  watch_dirs
  quiet=1
  cmd_sync

  command -v inotifywait >/dev/null 2>&1 || die "inotifywait is not installed"

  local self=$BASHPID parent
  parent=$(ps -o ppid= -p "$self" 2>/dev/null | tr -d ' ')
  start_watcher "$self"
  trap 'kill "$watcher" 2>/dev/null' EXIT INT TERM
  watch_loop "$self" "$parent"
}

# Sets the caller's dirs to the folders to watch, creating them.
watch_dirs() {
  if [[ $engine == omapager ]]; then
    # 4.5 keeps everything in two files; never recreate the old history/.
    mkdir -p "$src_dir" "$captures" && chmod 700 "$captures" 2>/dev/null
    dirs=("$src_dir")
  else
    mkdir -p "$src_dir" "$src_history"
    dirs=("$src_dir" "$src_history")
  fi
}

# Starts inotifywait on dirs as fd 3 and sets watcher to its pid.
# inotifywait must not outlive us. The EXIT trap only runs when we exit
# cleanly; when the shell restarts, this script can be SIGKILLed, and the
# watcher used to linger, reparented to systemd, one per restart. So the
# kernel kills it with us (setpriv --pdeathsig), or, without setpriv, a
# small guard does once our pid (SELF) is gone.
start_watcher() {
  local self=$1
  local -a deathsig=()
  if [[ -z ${YANC_NO_PDEATHSIG:-} ]] && command -v setpriv >/dev/null 2>&1 \
    && setpriv --pdeathsig TERM true 2>/dev/null; then
    deathsig=(setpriv --pdeathsig TERM --)
  fi
  exec 3< <(exec "${deathsig[@]}" inotifywait -m -q -e close_write -e moved_to --format '%w%f' \
    "${dirs[@]}" 2>/dev/null)
  watcher=$!
  if (( ${#deathsig[@]} == 0 )); then
    (while kill -0 "$self" 2>/dev/null; do sleep 1; done; kill "$watcher" 2>/dev/null) >/dev/null 2>&1 &
  fi
}

# Ingests every changed file inotifywait reports on fd 3.
watch_loop() {
  local self=$1 parent=$2 check=${YANC_WATCH_CHECK:-5} file rc now_parent
  while true; do
    IFS= read -r -t "$check" file <&3; rc=$?
    if (( rc > 128 )); then
      # Timed out: stop once whoever started us is gone (we were reparented)
      # or the watcher died.
      now_parent=$(ps -o ppid= -p "$self" 2>/dev/null | tr -d ' ')
      [[ -n $parent && $now_parent != "$parent" ]] && exit 0
      kill -0 "$watcher" 2>/dev/null || exit 1
      continue
    fi
    (( rc == 0 )) || break
    watch_event "$file"
  done
}

# One changed FILE: re-read the omapager files, or ingest a legacy file.
watch_event() {
  local file=$1
  if [[ $engine == omapager ]]; then
    [[ $file == "$engine_live" || $file == "$engine_history" ]] || return 0
    with_lock ingest_engine_one
    return 0
  fi
  [[ $file == *.json ]] || return 0
  is_under "$file" "$src_dir" || is_under "$file" "$src_history" || return 0
  with_lock ingest_one "$file"
}
