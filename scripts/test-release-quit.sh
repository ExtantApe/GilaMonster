#!/bin/bash
# Checks that the shutdown quit handler and the power-off observer are registered in every build, not only debug ones
# (6b44886: they once sat inside the debug-only block, so release builds stopped no servers at a Mac shutdown).
# Reads source only. Its self-test writes made-up files in its own temp folder and removes only that folder.
set -uo pipefail
cd "$(dirname "$0")/.."
root=$(mktemp -d "${TMPDIR:-/tmp}/leafjuice-quitcheck.XXXXXX")
trap 'rm -rf "$root"' EXIT
fail=0

# Prints each needed line that sits inside an `#if DEBUG` block of the given file.
debug_only() {
    awk '
        /^[[:space:]]*#if DEBUG/ { depth = 1; next }
        depth && /^[[:space:]]*#if/ { depth++ }
        depth && /^[[:space:]]*#endif/ { depth--; next }
        depth && /setEventHandler\(self, andSelector: #selector\(handleQuit|willPowerOffNotification/ { print FILENAME ":" NR }
    ' "$1"
}
has_both() { grep -q 'selector(handleQuit' "$1" && grep -q 'willPowerOffNotification' "$1"; }

src=Sources/LeafJuice/AppModel.swift
if ! has_both "$src"; then echo "FAILED: $src no longer registers both the quit handler and the power-off observer"; fail=1
elif [ -n "$(debug_only "$src")" ]; then echo "FAILED: debug-only registration at $(debug_only "$src" | tr '\n' ' ')"; fail=1
else echo "ok: the quit handler and the power-off observer are registered in release builds"; fi

# Self-test: the check catches a registration moved back inside a debug block.
printf '#if DEBUG\nNSAppleEventManager.shared().setEventHandler(self, andSelector: #selector(handleQuit(_:withReplyEvent:)),\nNSWorkspace.willPowerOffNotification\n#endif\n' > "$root/bad.swift"
if [ -n "$(debug_only "$root/bad.swift")" ]; then echo "ok: the check catches a debug-only registration"; else echo "FAILED: the check missed a debug-only registration"; fail=1; fi
exit $fail
