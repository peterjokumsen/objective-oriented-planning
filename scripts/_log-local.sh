# shellcheck shell=bash
# Local logging backend: colour when stdout is a TTY, plain text otherwise.
# Sourced by _log.sh, never directly. See _log-ghactions.sh for the GitHub
# Actions counterpart — both must define the same functions, which the `shell`
# job in .github/workflows/ci.yml checks.
#
# Levels are routed consistently with the GitHub backend: step/info/success/
# debug/group to stdout, warn/error to stderr, each also appended to the
# matching log file by _log_stdout/_log_stderr. That is why `warn` moved from
# stdout to stderr here: it is a diagnostic, and the split now matches what the
# three log files are named after. Never use these inside $(...) captures.

# Colour helpers: auto-disabled when output is not a TTY or NO_COLOR is set,
# so piped/logged output stays plain.
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  C_RESET=$'\e[0m'; C_BLUE=$'\e[34m'; C_GREEN=$'\e[32m'
  C_YELLOW=$'\e[33m'; C_RED=$'\e[31m'; C_CYAN=$'\e[36m'
else
  C_RESET=''; C_BLUE=''; C_GREEN=''; C_YELLOW=''; C_RED=''; C_CYAN=''
fi

step()    { _log_stdout "$(printf '%b==>%b %s' "$C_BLUE" "$C_RESET" "$*")"; }
info()    { _log_stdout "$(printf '%b%s%b' "$C_CYAN" "$*" "$C_RESET")"; }
success() { _log_stdout "$(printf '%b%s%b' "$C_GREEN" "$*" "$C_RESET")"; }
warn()    { _log_stderr "$(printf '%b%s%b' "$C_YELLOW" "$*" "$C_RESET")"; }
error()   { _log_stderr "$(printf '%b%s%b' "$C_RED" "$*" "$C_RESET")"; }
debug()   { _log_stdout "$(printf '%b%s%b' "$C_CYAN" "debug: $*" "$C_RESET")"; }

# group/endgroup bracket a noisy section (e.g. a retry loop). GitHub Actions
# collapses these; locally they are just banner lines, so a local log has the
# same shape as the CI one. Always pair them — an unbalanced endgroup swallows
# the rest of the step's output in CI.
group()    { _log_stdout "--- $* ---"; }
endgroup() { _log_stdout '---'; }
