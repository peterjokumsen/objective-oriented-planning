# shellcheck shell=bash
# GitHub Actions logging backend: workflow commands instead of colour, so
# messages become annotations and verbose sections can be collapsed.
# Sourced by log.sh, never directly. See log-local.sh for the local
# counterpart — both must define the same functions, which the `shell` job in
# .github/workflows/ci.yml checks.
#
# Everything goes to STDERR, deliberately. Two reasons:
#   * The scripts treat stdout as data: `run`, `group_exists` and
#     `fetch_deployment_outputs` are called inside $(...) captures, and
#     check-state.sh prints its report there. Keeping annotations on stdout
#     would splice `::error::…` text into a captured value.
#   * The runner parses workflow commands from both streams (it attaches the
#     same output manager to the process's stdout and stderr), even though the
#     docs only promise stdout. Both streams are rendered in the log, so this
#     is annotation-safe in the runner and never corrupts captured output.
# If a future runner ever stops parsing stderr, the log stays readable and only
# the annotations are lost — which is why messages carry no colour of their own.
#
# Two parser rules to respect: the command ends at the first unescaped newline
# or `\r`, and `%` starts an escape sequence, so both are percent-encoded here.
# Every line goes through _log_stderr, which also appends it to the stderr log.

# _gh_escape_data <text>: escape a workflow command's message payload.
_gh_escape_data() {
  local text="$*"
  text="${text//'%'/'%25'}"
  text="${text//$'\r'/'%0D'}"
  text="${text//$'\n'/'%0A'}"
  printf '%s' "$text"
}

# _gh_escape_prop <text>: escape a workflow command property value (title=,
# file=, ...), which additionally reserves the `:` and `,` separators.
# Unused for now — no printer takes properties — but kept next to the data
# escaper so adding a `title=` later cannot pick the wrong one.
_gh_escape_prop() {
  local text
  text="$(_gh_escape_data "$@")"
  text="${text//':'/'%3A'}"
  text="${text//','/'%2C'}"
  printf '%s' "$text"
}

# Only the levels worth annotating are workflow commands:
#   step    -> ::notice::    a milestone heading
#   warn    -> ::warning::  a diagnostic
#   error   -> ::error::     a failure
#   debug   -> ::debug::    only with step debug logging enabled
# info/success are plain text: they narrate routine progress, and annotating
# them made every teardown run read as a wall of equal-weight "Notice:" lines
# (10 notices in ~19 lines), which buried the warning and error that matter.
# They still go to stderr, matching the local backend's level-to-stream split,
# so a `$(...)` capture can never swallow them.
step()  { _log_stderr "::notice::$(_gh_escape_data "$*")"; }
warn()  { _log_stderr "::warning::$(_gh_escape_data "$*")"; }
error() { _log_stderr "::error::$(_gh_escape_data "$*")"; }
# Only visible when step debug logging is on (ACTIONS_STEP_DEBUG / the
# "Enable debug logging" workflow setting).
debug() { _log_stderr "::debug::$(_gh_escape_data "$*")"; }

info()    { _log_stderr "$*"; }
success() { _log_stderr "$*"; }

group()    { _log_stderr "::group::$(_gh_escape_data "$*")"; }
endgroup() { _log_stderr '::endgroup::'; }
