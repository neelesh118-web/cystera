#!/usr/bin/env bash
#
# Every check this repo has, in one run — and an honest label on each line
# saying whether that stage needed a phone.
#
# The three host stages are the analyzer, the host suite and the copy budget.
# The three device suites are not garnish (README, "Run"): sqflite_sqlcipher
# has no host implementation, so the DDL and every migration are parsed for the
# first time on a device; the alarms are the phone's alarm manager; the keystore
# is the phone's own. Nothing in the host suite can stand in for those.
#
# One thing deliberately stays manual: the notification readback
# (docs/reminders.md) needs a second shell while the reminders suite holds its
# windows — so this script runs that suite without the hold, and the skip and
# pass summaries both name the readback as the step a script cannot do alone.
#
# Usage:  bash tool/verify.sh
# Exit:   0 when everything that ran passed — a skipped phone stage is named
#         in the summary, not hidden — and 1 when any stage failed.
set -u
cd "$(dirname "$0")/.."

LOGDIR="$(mktemp -d)"
trap 'rm -rf "$LOGDIR"' EXIT

FAILED=0
RAN_PHONE=0

stage() {
  # stage <name> <label> <command...>
  local name="$1" label="$2"
  shift 2
  local log start
  log="$LOGDIR/$(printf '%s' "$name" | tr -c 'A-Za-z0-9' '_').log"
  printf '%-30s %-24s' "$name" "$label"
  start=$SECONDS
  if "$@" >"$log" 2>&1; then
    printf 'ok   (%ss)\n' "$((SECONDS - start))"
  else
    printf 'FAIL (%ss)\n' "$((SECONDS - start))"
    FAILED=1
    printf -- '---- last 25 lines of %s ----\n' "$name"
    tail -n 25 "$log"
    printf -- '----\n'
  fi
}

needs_phone() {
  # needs_phone <name> <what a phone would prove here>
  printf '%-30s %-24s skipped — connect a phone; this stage proves: %s\n' \
    "$1" "[needs a phone]" "$2"
}

echo 'Cystera — the whole verification stack'
echo

stage 'analyzer'    '[no phone]'  flutter analyze --no-pub
stage 'host suite'  '[no phone]'  flutter test
stage 'copy budget' '[no phone]'  dart run tool/hardcoded_copy.dart --check

# The phone, found once and named in every line that uses it. `flutter devices`
# wakes the adb server itself, which is why detection runs before the suites
# rather than trusting a device id from an earlier session.
DEVICES="$(flutter devices 2>/dev/null || true)"
PHONE="$(printf '%s\n' "$DEVICES" \
  | awk -F'•' '/android/ && NF >= 4 {gsub(/^[ \t]+|[ \t]+$/, "", $2); print $2; exit}')"

echo
if [ -n "$PHONE" ]; then
  echo "Phone: $PHONE — the three device suites run against it."
  RAN_PHONE=1
  stage 'device: logging_test'  "[phone $PHONE]" \
    flutter test integration_test/logging_test.dart -d "$PHONE"
  stage 'device: reminders_test' "[phone $PHONE]" \
    flutter test integration_test/reminders_test.dart -d "$PHONE"
  stage 'device: device_test'    "[phone $PHONE]" \
    flutter test integration_test/device_test.dart -d "$PHONE"
else
  echo 'No phone connected. What is left needs one — named, not skipped quietly:'
  needs_phone 'device: logging_test' \
    'every schema migration, SQLCipher DDL, the fresh-install table list'
  needs_phone 'device: reminders_test' \
    'real alarms, a fired one-shot disarming itself, POST_NOTIFICATIONS'
  needs_phone 'device: device_test' \
    'the keystore report, backup/restore through the file system, the launcher icon'
  echo
  echo 'Connect one, then re-run this script — or by hand:'
  echo '  flutter test integration_test/logging_test.dart -d <device-id>'
  echo '  flutter test integration_test/reminders_test.dart -d <device-id> --dart-define=cystera_hold_for_readback=true'
  echo '  flutter test integration_test/device_test.dart -d <device-id>'
  echo 'The notification readback stays manual either way (docs/reminders.md).'
fi

echo
if [ "$FAILED" -ne 0 ]; then
  echo 'FAILED — a stage above failed; its output tail is printed in place.'
  exit 1
fi
if [ "$RAN_PHONE" -eq 0 ]; then
  echo 'PARTIAL — every host check passed. The three device suites were skipped'
  echo 'and are named above; re-run this script with a phone for the full stack.'
else
  echo 'All checks passed — host and phone.'
fi
