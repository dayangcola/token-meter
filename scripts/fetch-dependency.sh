#!/bin/zsh
set -euo pipefail
project_root=${0:A:h:h}
dependency_dir="$project_root/vendor/CodexBar"
mkdir -p "$dependency_dir"
archive=$(mktemp /private/tmp/aiquota-dependency.XXXXXX)
trap 'rm -f "$archive"' EXIT
/usr/bin/curl -fsSL --max-time 120 'https://github.com/steipete/CodexBar/releases/download/v0.84.0/CodexBarCLI-v0.84.0-macos-arm64.tar.gz' -o "$archive"
expected='77a318c6b904983711f1b7d248211b1bbd4a77b5e038258a79ba2258683f2603'
actual=$(/usr/bin/shasum -a 256 "$archive" | /usr/bin/awk '{print $1}')
[[ "$actual" == "$expected" ]] || { print -u2 'CodexBar checksum mismatch'; exit 1; }
/usr/bin/tar -xzf "$archive" -C "$dependency_dir"
/usr/bin/curl -fsSL --max-time 30 'https://raw.githubusercontent.com/steipete/CodexBar/v0.84.0/LICENSE' -o "$dependency_dir/LICENSE"
print 'CodexBar 0.84.0 verified.'
