#!/bin/bash
# NotchDash statusline 旁路
#
# Claude Code 每次刷新状态栏，会把一包 JSON 从 stdin 喂给状态栏程序，其中
# rate_limits 就是官方的额度数据（v2.1.6+）。本脚本做两件事：
#   ① 抄一份交给 NotchDash，提取额度存成快照
#   ② 原样转发给「下游」状态栏程序，终端里看到的状态栏不受影响
#
# 下游程序的选择顺序：
#   1. 环境变量 NOTCHDASH_DOWNSTREAM 指定的命令
#   2. 自动探测到的 claude-hud 插件
#   3. 都没有的话，输出一行极简状态栏
set -uo pipefail

INPUT=$(cat)

# ── ① 抄一份给 NotchDash ─────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
for candidate in \
  "${NOTCHDASH_BIN:-}" \
  "$HOME/Applications/NotchDash.app/Contents/MacOS/NotchDash" \
  "$SCRIPT_DIR/../build/NotchDash.app/Contents/MacOS/NotchDash" \
  "/Applications/NotchDash.app/Contents/MacOS/NotchDash"
do
  if [ -n "$candidate" ] && [ -x "$candidate" ]; then
    # 出任何问题都不能影响状态栏，整段吞掉错误
    printf '%s' "$INPUT" | "$candidate" --statusline-tee >/dev/null 2>&1 || true
    break
  fi
done

# ── ② 转发给下游 ────────────────────────────────────────
if [ -n "${NOTCHDASH_DOWNSTREAM:-}" ]; then
  printf '%s' "$INPUT" | eval "$NOTCHDASH_DOWNSTREAM"
  exit $?
fi

# 自动探测 claude-hud（装了就用，没装就跳过）
hud_dir=$(ls -d "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"/plugins/cache/*/claude-hud/*/ 2>/dev/null \
  | awk -F/ '{ print $(NF-1) "\t" $0 }' \
  | grep -E '^[0-9]+\.[0-9]+\.[0-9]+[[:space:]]' \
  | sort -t. -k1,1n -k2,2n -k3,3n -k4,4n | tail -1 | cut -f2- || true)

node_bin="${NOTCHDASH_NODE:-$(command -v node 2>/dev/null || true)}"
if [ -z "$node_bin" ]; then
  # PATH 里没有 node 时，在 fnm / nvm / homebrew 的常见位置找一下
  node_bin=$(ls -t "$HOME"/.local/share/fnm/node-versions/*/installation/bin/node \
                   "$HOME"/.nvm/versions/node/*/bin/node \
                   /opt/homebrew/bin/node /usr/local/bin/node 2>/dev/null | head -1 || true)
fi

if [ -n "$hud_dir" ] && [ -f "${hud_dir}dist/index.js" ] && [ -n "$node_bin" ]; then
  cols=$(stty size </dev/tty 2>/dev/null | awk '{print $2}')
  export COLUMNS=$(( ${cols:-120} > 4 ? ${cols:-120} - 4 : 1 ))
  # 注意：这里不能用 exec —— 管道里的 exec 只替换子 shell，主脚本会继续往下
  # 跑到兜底分支，导致状态栏输出两遍
  printf '%s' "$INPUT" | "$node_bin" "${hud_dir}dist/index.js"
  exit $?
fi

# 兜底：极简状态栏，至少不是一片空白
printf '%s' "$INPUT" | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
    model = d.get("model", {}).get("display_name", "")
    rl = d.get("rate_limits") or {}
    bits = [model] if model else []
    for key, tag in (("five_hour", "5h"), ("seven_day", "7d")):
        w = rl.get(key) or {}
        p = w.get("used_percentage")
        if p is not None:
            bits.append(f"{tag} {round(p)}%")
    print(" │ ".join(bits) or "NotchDash")
except Exception:
    print("NotchDash")
' 2>/dev/null || echo "NotchDash"
