#!/usr/bin/env bash
# Logging self-check: drives every printer and every command-log helper through
# both backends, offline (no `az`, no .env, no Azure), and asserts what the
# console streams, the three log files and the workflow summary are each
# supposed to contain. The `shell` job in .github/workflows/ci.yml runs this on
# every PR.
#
#   ./scripts/check-logging.sh                 emit with both backends, then check
#   LOG_FORMAT=local ./scripts/check-logging.sh --emit    emit only (child mode)
#
# Why it exists: one message deliberately lands in four places (a console
# stream, one of the three log files, and — under the GitHub backend — the step
# summary). Every one of those splits is easy to break in a way nothing else
# notices: an `info` that silently stops reaching the stderr log, an unbalanced
# `::group::` that swallows the rest of a step, an `exit` where a `return`
# belonged and killed the calling script mid-teardown. Those only surface while
# reading a failed run's log, i.e. after the fact; this makes them fail on the
# PR instead. scripts/check-logging.sh also covers the backends' shared function
# list (the parity check in ci.yml), so the two never drift apart.
set -euo pipefail

SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---------------------------------------------------------------- assertions --
_failures=0

ok() { printf '  ok    %s\n' "$*"; }
bad() { printf '  FAIL  %s\n' "$*"; _failures=$((_failures + 1)); }

# check <description> <command...>: run the command, report ok/FAIL on its exit
# status. The command is a predicate (_contains/_lacks/_count_eq/… below).
check() {
  local desc="$1"
  shift
  if "$@"; then ok "$desc"; else bad "$desc"; fi
}

_is_zero() { [[ "$1" == "0" ]]; }
_is_not_zero() { [[ "$1" != "0" ]]; }

_has() { grep -qF -- "$2" "$1"; }
_lacks() { ! grep -qF -- "$2" "$1"; }

# _count_eq <file> <needle> <expected>: how many lines contain the needle. Used
# for the pairs that only balance: ::group::/::endgroup::, <details>/</details>.
_count_eq() {
  local file="$1" needle="$2" expected="$3" actual
  actual="$(grep -cF -- "$needle" "$file" || true)"
  [[ "$actual" == "$expected" ]] ||
    printf '        %s has %s line(s) containing %s, expected %s\n' \
      "$file" "$actual" "$needle" "$expected" >&2
  [[ "$actual" == "$expected" ]]
}

# _exactly_one <dir> <glob>: init_command_log's contract is exactly one file per
# kind. The glob stays unquoted so the shell expands it here, where the loop can
# count the misses too (a literal path would just fail to list).
_exactly_one() {
  local dir="$1" pattern="$2" found=0 f
  for f in "$dir"/$pattern; do
    if [[ -e "$f" ]]; then found=$((found + 1)); fi
  done
  [[ "$found" == "1" ]]
}

# ------------------------------------------------------------------- emitting --
# Child mode. LOG_WORKDIR points $ROOT at a temp dir so init_command_log writes
# its three files there instead of polluting the repo's logs/.
_emit() {
  ROOT="${LOG_WORKDIR:-$(cd "$SCRIPTS_DIR/.." && pwd)}"
  export ROOT
  source "$SCRIPTS_DIR/_log.sh"

  init_command_log "logging-demo"
  log_vars "Backend=$LOG_FORMAT" "Attempts=2" "Verbose=on"

  step "Step one: messages"
  info "an info message"
  success "a success message"
  warn "a warn message"
  error "an error message"
  debug "a debug message"
  # Newlines and % are the two things the GitHub backend has to escape in a
  # workflow command; a message with both proves it.
  debug "multi
line 100% message"

  # The summary block a caller composes by hand (a results table, say). Must
  # arrive verbatim, not as one info bullet per line.
  summary ""
  summary "## Logging demo"
  summary ""
  summary "| Level | Reaches the summary |"
  summary "| --- | --- |"

  step "Step two: command log"
  # The <script> and the & in the title are deliberate: a <summary> title is raw
  # markup, so the backend has to escape all three characters that can break out
  # of the element — and bash eats an unquoted & in a pattern substitution, which
  # is exactly the sort of bug only an emitted run can catch.
  group "Command variants <script> & friends"
  info "info inside a group"
  run printf 'stdout from run\n'
  run bash -c 'printf "stderr from run\n" >&2'
  run_hide_stderr bash -c 'printf "hidden stderr\n" >&2'
  run_quiet printf 'hidden stdout\n'
  if run bash -c 'printf "expected failure\n" >&2; exit 1'; then
    warn "run reported success for a command that was meant to fail"
  else
    info "run propagated a non-zero exit status"
  fi
  endgroup

  step "Step three: outcome"
  success "demo finished"
}

if [[ "${1:-}" == "--emit" ]]; then
  _emit
  exit 0
fi

# ------------------------------------------------------------------- checking --
# The parent logs with the local backend regardless of the environment, and
# without GITHUB_STEP_SUMMARY: the summary file belongs to the child, so its
# contents are exactly what that one emit produced and nothing this script does.
ROOT="$(cd "$SCRIPTS_DIR/.." && pwd)"
LOG_FORMAT=local
unset GITHUB_STEP_SUMMARY
source "$SCRIPTS_DIR/_log.sh"

# One temp dir per backend run; a failed assertion keeps nothing behind.
WORKDIRS=()
cleanup() { local d; for d in ${WORKDIRS+"${WORKDIRS[@]}"}; do rm -rf "$d"; done; }
trap cleanup EXIT

# run_backend <backend>: emit once with LOG_FORMAT set, capture the console
# streams, and assert the invariants that hold for *either* backend. The paths
# it checked are left in the CONSOLE_OUT/… globals rather than printed: the
# parent logs with the local backend, whose step/info go to stdout, so anything
# printed here would be indistinguishable from a captured path list.
run_backend() {
  local backend="$1"
  local rc=0

  workdir="$(mktemp -d)"
  WORKDIRS+=("$workdir")
  CONSOLE_OUT="$workdir/console.out"
  CONSOLE_ERR="$workdir/console.err"
  SUMMARY_FILE="$workdir/step-summary.md"

  # GITHUB_STEP_SUMMARY is set for both backends on purpose: `summary` writes to
  # it regardless of the backend, so this also proves the markdown blocks a
  # caller composes reach it even when the console prints them locally.
  LOG_FORMAT="$backend" \
  LOG_WORKDIR="$workdir" \
  GITHUB_STEP_SUMMARY="$SUMMARY_FILE" \
    "$0" --emit >"$CONSOLE_OUT" 2>"$CONSOLE_ERR" || rc=$?

  step "Backend: $backend"

  check "emit exits 0" _is_zero "$rc"
  check "commands log created" _exactly_one "$workdir/logs" '*_commands.log'
  check "stdout log created" _exactly_one "$workdir/logs" '*_stdout.log'
  check "stderr log created" _exactly_one "$workdir/logs" '*_stderr.log'

  commands_log="$(ls "$workdir"/logs/*_commands.log)"
  STDOUT_LOG="$(ls "$workdir"/logs/*_stdout.log)"
  STDERR_LOG="$(ls "$workdir"/logs/*_stderr.log)"
  local stdout_log="$STDOUT_LOG" stderr_log="$STDERR_LOG"

  # --- the command log: one trace per run* call, console-quiet optional ------
  check "commands log has the run trace" _has "$commands_log" "+ printf stdout"
  check "commands log has the failing run" _has "$commands_log" "+ bash -c"
  check "commands log has every run" \
    _count_eq "$commands_log" "+ " 5

  # --- stdout log: command stdout only (level routing is per backend) -------
  check "stdout log has run's stdout" _has "$stdout_log" "stdout from run"
  # run_quiet hides the console only — the file must still have it, or a quiet
  # command's output would be lost from the transcript.
  check "stdout log has run_quiet's output" _has "$stdout_log" "hidden stdout"
  # Streams are separate, not an interleaved transcript: a command's stderr
  # must not turn up in the stdout log.
  check "stdout log has no stderr from run" _lacks "$stdout_log" "stderr from run"
  check "stdout log has no hidden stderr" _lacks "$stdout_log" "hidden stderr"

  # --- stderr log: command stderr + the diagnostic levels -------------------
  check "stderr log has run's stderr" _has "$stderr_log" "stderr from run"
  check "stderr log has run_hide_stderr's output" _has "$stderr_log" "hidden stderr"
  check "stderr log has the failing command's stderr" _has "$stderr_log" "expected failure"
  check "stderr log has the warn message" _has "$stderr_log" "a warn message"
  check "stderr log has the error message" _has "$stderr_log" "an error message"
  # run_quiet must not leak its stderr here either — nothing to check beyond the
  # trace, but its stdout must be absent from stderr: already implied above.

  # --- console: run_quiet/run_hide_stderr stay off both console streams ------
  check "console stdout has run's stdout" _has "$CONSOLE_OUT" "stdout from run"
  check "console stdout hides run_quiet's output" _lacks "$CONSOLE_OUT" "hidden stdout"
  check "console stdout hides stderr from run" _lacks "$CONSOLE_OUT" "stderr from run"
  check "console stdout hides hidden stderr" _lacks "$CONSOLE_OUT" "hidden stderr"

  # --- the hand-written summary block, verbatim, on both backends -----------
  check "summary has the markdown heading" _has "$SUMMARY_FILE" "## Logging demo"
  check "summary has the table header" _has "$SUMMARY_FILE" "| Level | Reaches the summary |"
  check "summary does not turn it into info bullets" _lacks "$SUMMARY_FILE" "- **info** |"
}

# check_github: what only the workflow backend has to get right — annotations on
# stderr, workflow commands for the collapsible sections, and the summary page.
check_github() {
  local console_out="$CONSOLE_OUT" console_err="$CONSOLE_ERR" summary_file="$SUMMARY_FILE"
  local stdout_log="$STDOUT_LOG" stderr_log="$STDERR_LOG"

  step "Backend: github — workflow commands and the summary"

  # Everything the backend prints goes to stderr, so a $(...) capture of a
  # helper's stdout can never pick up an ::annotation::.
  check "console stdout stays free of chatter" _lacks "$console_out" "an info message"
  check "console stdout stays free of step headings" _lacks "$console_out" "Step one"
  check "no workflow command leaked into the stdout log" _lacks "$stdout_log" "::"
  # The same split holds for the log files: the local backend sends step/info/
  # success/debug/group to the stdout log, this one sends them to the stderr log
  # (see the header of _log-ghactions.sh). Command output routes identically on
  # both, so only the levels differ.
  check "stdout log has no info message" _lacks "$stdout_log" "an info message"
  check "stdout log has no success message" _lacks "$stdout_log" "a success message"
  check "stderr log has the info message" _has "$stderr_log" "an info message"
  check "stderr log has the success message" _has "$stderr_log" "a success message"
  check "stderr log has the step heading" _has "$stderr_log" "Step one: messages"
  check "stderr log has no stdout command output" _lacks "$stderr_log" "stdout from run"

  check "warn is a ::warning:: annotation" _has "$console_err" "::warning::a warn message"
  check "error is a ::error:: annotation" _has "$console_err" "::error::an error message"
  check "debug is a ::debug:: annotation" _has "$console_err" "::debug::a debug message"
  # The command ends at the first newline and % starts an escape, so a
  # multi-line message with a % has to be escaped rather than emitted raw.
  check "multi-line debug message is escaped" _has "$console_err" "%0A"
  check "percent in a message is escaped" _has "$console_err" "%25"
  check "annotations reach the stderr log" _has "$stderr_log" "::warning::"
  check "group opens a log section" _has "$console_err" "::group::Command variants"
  check "group is closed exactly once" _count_eq "$console_err" "::endgroup::" 1
  check "group is opened exactly once" _count_eq "$console_err" "::group::" 1

  check "summary has a heading per step" _count_eq "$summary_file" "## Step " 3
  check "summary has a done bullet" _has "$summary_file" "- **done** a success message"
  check "summary has an info bullet" _has "$summary_file" "- **info** an info message"
  check "summary has a warn bullet" _has "$summary_file" "- **warn** a warn message"
  check "summary has an error bullet" _has "$summary_file" "- **error** an error message"
  # A group collapses in the log, so it must collapse in the summary too — an
  # unterminated <details> would swallow every step that follows it.
  check "summary opens a details block" \
    _has "$summary_file" "<summary>Command variants &lt;script&gt; &amp; friends</summary>"
  check "details block is opened once" _count_eq "$summary_file" "<details>" 1
  check "details block is closed once" _count_eq "$summary_file" "</details>" 1
  # The block's own bullets nest inside it, since they are emitted between
  # group and endgroup.
  check "the group's bullets land inside the block" \
    _inside_details "$summary_file" "- **info** info inside a group"
  # A raw `<script>` or `&` in the title would leak through as markup and break
  # the rest of the summary page.
  check "summary titles have no raw markup" _lacks "$summary_file" "<script>"
  check "summary titles escape the ampersand" _lacks "$summary_file" "variants & friends"
  # Closing the block matters: an unterminated <details> swallows every step
  # that follows, so the last heading must come after </details>.
  check "later steps follow the details block" \
    _after_details "$summary_file" "## Step three"
}

# check_local: what only the TTY backend has to get right — and, above all, that
# it emits nothing the runner would try to parse as a workflow command.
check_local() {
  local console_out="$CONSOLE_OUT" console_err="$CONSOLE_ERR" summary_file="$SUMMARY_FILE"
  local stdout_log="$STDOUT_LOG" stderr_log="$STDERR_LOG"

  step "Backend: local — no workflow commands anywhere"

  check "step headings are on stdout" _has "$console_out" "==> Step one"
  check "info is on stdout" _has "$console_out" "an info message"
  check "warn is on stderr" _has "$console_err" "a warn message"
  check "error is on stderr" _has "$console_err" "an error message"
  check "group brackets a banner on stdout" _has "$console_out" "--- Command variants"
  # Level routing for the log files is the mirror image of the GitHub backend:
  # step/info/success/debug/group go to the stdout log there, to the stderr log
  # here. Command output routes identically on both.
  check "stdout log has the info message" _has "$stdout_log" "an info message"
  check "stdout log has the success message" _has "$stdout_log" "a success message"
  check "stdout log has the step heading" _has "$stdout_log" "Step one: messages"
  check "stdout log has no warn message" _lacks "$stdout_log" "a warn message"
  check "stdout log has no error message" _lacks "$stdout_log" "an error message"
  check "stderr log has no stdout command output" _lacks "$stderr_log" "stdout from run"
  # The point of the backend: a local run must never emit text the runner would
  # try to parse as a workflow command.
  check "no ::error:: in the console" _lacks "$console_err" "::error::"
  check "no ::warning:: in the console" _lacks "$console_err" "::warning::"
  check "no workflow commands in the stderr log" _lacks "$stderr_log" "::"
  check "no details block in the summary" _lacks "$summary_file" "<details>"
  check "no summary bullets in the summary" _lacks "$summary_file" "- **"
}

# _inside_details <file> <needle>: the needle appears between the first
# <details> and the matching </details>.
_inside_details() {
  sed -n '/<details>/,/<\/details>/p' "$1" | grep -qF -- "$2"
}

# _after_details <file> <needle>: the needle appears after the last </details>.
_after_details() {
  sed -n '/<\/details>/,$p' "$1" | grep -qF -- "$2"
}

step "check-logging: driving both logging backends"

run_backend local
check_local

run_backend github
check_github

# An unknown backend must fail loudly instead of silently losing every message.
step "check-logging: LOG_FORMAT validation"
rc=0
LOG_FORMAT=twitch "$0" --emit >/dev/null 2>&1 || rc=$?
check "unknown LOG_FORMAT exits non-zero" _is_not_zero "$rc"

if ((_failures > 0)); then
  error "$_failures logging assertion(s) failed."
  exit 1
fi
success "All logging assertions passed."
