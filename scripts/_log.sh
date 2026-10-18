# shellcheck shell=bash
# Logging utilities: the message printers (one backend, picked below) plus the
# command-log helpers every script uses. Sourced by common.sh — never run
# directly. Nothing here is an entry point; the `_` prefix marks it as such.
#
# Backends (_log-local.sh / _log-ghactions.sh) define an identical set of
# functions: step info success warn error debug group endgroup.
#
# LOG_FORMAT picks one:
#   auto    (default) GitHub Actions backend when GITHUB_ACTIONS=true, else local
#   github  force workflow commands (useful for eyeballing CI output locally)
#   local   force the TTY/colour backend
# LOG_FORMAT is only read when unset, so an explicit choice always wins.
if [[ -z "${LOG_FORMAT:-}" ]]; then
  if [[ "${GITHUB_ACTIONS:-}" == "true" ]]; then
    LOG_FORMAT="github"
  else
    LOG_FORMAT="local"
  fi
fi

_LOG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# _log_stdout/_log_stderr: the single write path for both backends' messages,
# so script-level chatter (step/info/warn/error/annotations, not just command
# output) also lands in the stdout/stderr logs. Two plain writes — append to
# the log, then the console — so nothing depends on a pipe staying open, and
# buffering never delays a message. Called before the backend is sourced.
_log_stdout() {
  if [[ -n "${STDOUT_LOG:-}" ]]; then
    printf '%s\n' "$*" >> "$STDOUT_LOG"
  fi
  printf '%s\n' "$*"
}

_log_stderr() {
  if [[ -n "${STDERR_LOG:-}" ]]; then
    printf '%s\n' "$*" >> "$STDERR_LOG"
  fi
  printf '%s\n' "$*" >&2
}

case "$LOG_FORMAT" in
  local)
    # shellcheck source=_log-local.sh
    source "${_LOG_DIR}/_log-local.sh"
    ;;
  github)
    # shellcheck source=_log-ghactions.sh
    source "${_LOG_DIR}/_log-ghactions.sh"
    ;;
  *)
    printf 'Unknown LOG_FORMAT: %s (expected auto, local or github)\n' "$LOG_FORMAT" >&2
    return 1 2>/dev/null || exit 1
    ;;
esac

# summary <markdown>: append a block to the workflow run's summary page
# ($GITHUB_STEP_SUMMARY), which renders above the log where it is actually read
# — a 30-minute teardown log is a scroll, the summary is a table. Also echoes the
# text to the console, so a local run shows what CI would have summarised. The
# file only exists on a runner, so locally the console echo is all there is —
# nothing is lost either way. Top level only: the backends keep chatter off
# stdout and the summary file is shared per step, so a $(...) capture must not
# reach here.
summary() {
  if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
    printf '%s\n' "$*" >> "$GITHUB_STEP_SUMMARY"
  fi
  # Console echo via _log_stderr, not `info`: the GitHub backend now writes every
  # `info` to the summary as an `- **info** …` bullet, so a markdown block passed
  # through `info` would land there twice — once verbatim, once as a pile of
  # bullets per line. _log_stderr is the backend-neutral write path and keeps the
  # chatter off stdout, so a $(...) capture stays clean on both backends.
  _log_stderr "$*"
}

log_vars() {
  # Two passes so the values align: first find the widest "key:", then print.
  # (A fixed width breaks as soon as a longer key like "Shared resource group"
  # shows up.) Lines go through `info` rather than a bare printf so the GitHub
  # backend turns each one into a notice instead of invisible plain output.
  local width=0 kvp key line
  for kvp in "$@"; do
    key="${kvp%%=*}:"
    if (( ${#key} > width )); then
      width=${#key}
    fi
  done
  for kvp in "$@"; do
    printf -v line '  %-*s %s' "$width" "${kvp%%=*}:" "${kvp#*=}"
    info "$line"
  done
}

# --- command log -------------------------------------------------------------
#
# init_command_log <name> creates three files under $ROOT/logs:
#   <name>-YYYYmmdd-HHMMSS_commands.log  the `+ az …` traces
#   <name>-YYYYmmdd-HHMMSS_stdout.log    stdout: command output + step/info/
#                                       success/debug/group messages
#   <name>-YYYYmmdd-HHMMSS_stderr.log    stderr: command output + warn/error
# Separate streams (not one interleaved transcript) so a failure can be read
# without the noise, and so nothing has to guess which stream a line came from.
# All three are set together by init_command_log; each may also be exported
# beforehand on its own, and the helpers below cope with any subset being set.
#
# run echoes the command (`+ az ...`) to stderr, appends it to the commands log,
# then executes the command — with its stdout and stderr appended to their own
# logs as well. Console behaviour is deliberately unchanged: stdout still goes
# to stdout and stderr to stderr, which is what keeps `X=$(run az ...)`
# capturing only the command's own stdout. Use `run` for every `az`/`curl` call,
# including inside `if` conditions and `$(...)` captures. When an error exit is
# an expected outcome (e.g. probing for a resource that may not exist yet), use
# `run_hide_stderr` (hides the command's stderr on the console, but still logs
# it) or `run_quiet` (hides stdout on the console too) instead of appending
# `2>/dev/null` to `run` — a redirect on `run` itself would swallow the `+` trace.
export COMMAND_LOG="${COMMAND_LOG:-}"
export STDOUT_LOG="${STDOUT_LOG:-}"
export STDERR_LOG="${STDERR_LOG:-}"

init_command_log() {
  local name="${1:?usage: init_command_log <name>}"
  local stamp
  stamp="$(date -u +%Y%m%d-%H%M%S)"
  mkdir -p "$ROOT/logs"
  COMMAND_LOG="$ROOT/logs/${name}-${stamp}_commands.log"
  STDOUT_LOG="$ROOT/logs/${name}-${stamp}_stdout.log"
  STDERR_LOG="$ROOT/logs/${name}-${stamp}_stderr.log"
  export COMMAND_LOG STDOUT_LOG STDERR_LOG
  # `info`, not `debug`: under Actions a ::debug:: line is invisible unless the
  # whole job runs with debug logging, so the run gave no hint that a transcript
  # existed or where it was. The workflow uploads these paths as an artifact.
  info "Logs: $COMMAND_LOG | $STDOUT_LOG | $STDERR_LOG"
}

# _join_quoted: shell-quote each arg (%q) so the logged line is copy-pasteable.
_join_quoted() {
  local out="" a piece
  for a in "$@"; do
    piece=$(printf '%q' "$a")
    if [[ -z "$out" ]]; then
      out="$piece"
    else
      out="$out $piece"
    fi
  done
  printf '%s' "$out"
}

# log_cmd [args...]: echo the command to stderr and record it in the commands
# log. Set TRACE_COMMANDS=0 to silence the console trace — the log file, if
# any, still records it. Used by `check-state.sh --rg`, whose output is read by
# a CI step where a wall of `+ az ...` lines is pure noise.
log_cmd() {
  local cmd
  cmd=$(_join_quoted "$@")
  if [[ "${TRACE_COMMANDS:-1}" != "0" ]]; then
    printf '+ %s\n' "$cmd" >&2
  fi
  if [[ -n "${COMMAND_LOG:-}" ]]; then
    printf '+ %s\n' "$cmd" >> "$COMMAND_LOG"
  fi
}

# _tee_stderr: duplicate a command's stderr into the stderr log while leaving
# it on the console's stderr. Process substitution (rather than `2>&1`) keeps
# stderr out of a caller's `$(...)` capture. `cat` is the no-log passthrough.
# CAVEAT: a process substitution is not waited for, so a burst of stderr can
# reach the log just after the next command's trace line.
_tee_stderr() {
  if [[ -n "${STDERR_LOG:-}" ]]; then
    tee -a "$STDERR_LOG" >&2
  else
    cat >&2
  fi
}

run() {
  log_cmd "$@"
  if [[ -z "${STDOUT_LOG:-}${STDERR_LOG:-}" ]]; then
    "$@"
    return $?
  fi
  "$@" 2> >(_tee_stderr) | tee -a "${STDOUT_LOG}"
  return "${PIPESTATUS[0]}"
}

# Hides the command's stderr on the console but keeps it in the stderr log: the
# "resource does not exist" probes rely on it, and a failed probe is exactly
# what you want to find in the log afterwards.
run_hide_stderr() {
  log_cmd "$@"
  if [[ -z "${STDOUT_LOG:-}${STDERR_LOG:-}" ]]; then
    "$@" 2>/dev/null
    return $?
  fi
  if [[ -n "${STDERR_LOG:-}" ]]; then
    # Append straight to the file (no tee): nothing has to write it from two
    # places, so ordering inside the stderr log stays exactly as emitted.
    "$@" 2>>"$STDERR_LOG" | tee -a "$STDOUT_LOG"
  else
    "$@" 2>/dev/null | tee -a "$STDOUT_LOG"
  fi
  return "${PIPESTATUS[0]}"
}

run_quiet() {
  log_cmd "$@"
  if [[ -n "${STDOUT_LOG:-}" ]]; then
    "$@" >>"$STDOUT_LOG" 2>>"${STDERR_LOG:-/dev/null}"
    return $?
  fi
  "$@" >/dev/null 2>&1
}
