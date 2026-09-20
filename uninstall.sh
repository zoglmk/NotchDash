#!/bin/bash
# NotchDash 卸载：把动过的东西全部还原
set -uo pipefail

# 两个位置都清理，不确定当初装在哪
APPS=("/Applications/NotchDash.app" "$HOME/Applications/NotchDash.app")
PLIST="$HOME/Library/LaunchAgents/app.notchdash.NotchDash.plist"

echo "① 停止运行"
launchctl bootout "gui/$UID/app.notchdash.NotchDash" 2>/dev/null || true
pkill -f "NotchDash" 2>/dev/null || true
rm -f "$PLIST"

echo "② 还原 Claude Code 状态栏配置"
python3 - <<'PY'
import json, os, sys
p = os.path.expanduser('~/.claude/settings.json')
try:
    d = json.load(open(p, encoding='utf-8'))
except Exception as e:
    print('   跳过：读不到 settings.json（%s）' % e); sys.exit()
sl = d.get('statusLine', {})
orig = sl.pop('_notchdash_original_command', None)
if orig:
    sl['command'] = orig
    d['statusLine'] = sl
    open(p, 'w', encoding='utf-8').write(json.dumps(d, indent=2, ensure_ascii=False) + '\n')
    print('   已还原为原来的状态栏命令')
else:
    print('   没找到备份的原命令，未改动')
PY

echo "③ 删除应用"
for a in "${APPS[@]}"; do
  [ -d "$a" ] && rm -rf "$a" && echo "   已删除 $a"
done

echo
echo "✅ 已卸载。以下内容保留着，需要的话自己删："
echo "   ~/.notchdash/            （配置和额度快照）"
echo "   ~/.claude/settings.json.notchdash-backup-*  （配置备份）"
