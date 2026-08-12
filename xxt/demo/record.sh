#!/usr/bin/env bash
# Regenerate docs/demo.gif, the README recording, from xxt/demo/demo.tape.
#
# Needs: vhs (brew install vhs — bundles ttyd and a headless Chromium),
# the "Maple Mono NF" font installed system-wide, and the sibling
# checkouts the launch command runs against (../Selkie,
# ../Notcurses-Native). Records against a throwaway data home in
# /tmp/moneymoor-demo — never against ~/.moneymoor.
set -euo pipefail

cd "$(dirname "$0")/../.."

command -v vhs >/dev/null 2>&1 || {
    echo "vhs not found — brew install vhs" >&2
    exit 1
}

demo_home=/tmp/moneymoor-demo
rm -rf "$demo_home"
mkdir -p "$demo_home"
# GBP and '.' are the app defaults; written anyway so the recording is
# deterministic if those defaults ever move. Nerd icons are the one
# real opt-in.
printf '{"currency":"£","decimal_mark":".","icons":"nerd","theme":"gruvbox"}' \
    > "$demo_home/config.json"

# Warm the precomp cache (and the MacOS::NativeLib sqlcipher shim) so
# the tape's 8s launch window is enough even on a cold checkout.
raku -I lib -I ../Selkie/lib -I ../Notcurses-Native/lib -c bin/moneymoor >/dev/null

vhs xxt/demo/demo.tape

rm -rf "$demo_home"
ls -lh docs/demo.gif
