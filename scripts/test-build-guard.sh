#!/bin/bash
# Checks that scripts/build-app.sh refuses to build over a bundle something is running from (2026-11-17),
# and goes ahead when nothing is. Uses a made-up bundle in its own temp folder and removes only what it made.
set -uo pipefail
cd "$(dirname "$0")/.."
root=$(mktemp -d "${TMPDIR:-/tmp}/leafjuice-guard.XXXXXX")
pid=""
cleanup() {
    [ -n "$pid" ] && kill "$pid" 2>/dev/null && wait "$pid" 2>/dev/null
    rm -rf "$root"
}
trap cleanup EXIT
fail=0
ok() { echo "ok: $1"; }
bad() { echo "FAILED: $1"; fail=1; }

macos="$root/out/LeafJuice.app/Contents/MacOS"
mkdir -p "$macos"
printf 'int main(void){for(;;){} }\n' > "$root/spin.c"
cc -o "$macos/LeafJuice" "$root/spin.c" || { echo "FAILED: no C compiler"; exit 1; }

scripts/build-app.sh --out "$root/out" --guard-only >/dev/null 2>&1 && ok "nothing running: the build may go ahead" || bad "nothing running, but the guard refused"

"$macos/LeafJuice" & pid=$!
sleep 0.5
msg=$(scripts/build-app.sh --out "$root/out/" --guard-only 2>&1); code=$?
[ "$code" = 3 ] && ok "app running from the bundle: refused (exit 3)" || bad "app running, guard exited $code"
echo "$msg" | grep -q "is in use" && ok "and says why" || bad "refusal didn't say why: $msg"
[ -x "$macos/LeafJuice" ] && ok "and the bundle is left alone" || bad "the bundle was touched"

other="$root/elsewhere"; mkdir -p "$other"
scripts/build-app.sh --out "$other" --guard-only >/dev/null 2>&1 && ok "another folder: allowed while the app runs" || bad "another folder was refused"

scripts/build-app.sh --out "$root/new/folder" --guard-only >/dev/null 2>&1 && ok "a folder that doesn't exist yet: made, and allowed" || bad "a new folder failed"

kill "$pid"; wait "$pid" 2>/dev/null; pid=""
scripts/build-app.sh --out "$root/out" --guard-only >/dev/null 2>&1 && ok "after quitting: allowed again" || bad "still refused after quitting"
exit $fail
