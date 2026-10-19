#!/bin/bash
# Safe end-to-end verification against a real MQ80.
# - read-only info/selftest
# - full backup to /tmp
# - "write back identical keymap + verify" (writes only the same values)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="${1:-$ROOT/.build-manual/iqunixctl}"
export TMPDIR="${TMPDIR:-$ROOT/.build-manual/tmp}"

if [ ! -x "$BIN" ]; then
  echo "找不到 $BIN，请先运行 ./scripts/build.sh release" >&2
  exit 1
fi

echo "== 1/4 info =="
"$BIN" info

echo "== 2/4 selftest (只读) =="
"$BIN" selftest

echo "== 3/4 完整备份 =="
"$BIN" backup /tmp/iqunix-drive-verify-backup.json

echo "== 4/4 原样写回 + 回读校验 =="
"$BIN" writeback-test

echo "全部验证通过 ✅"
