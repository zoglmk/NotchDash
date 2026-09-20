#!/bin/bash
# NotchDash 安装脚本
#   ./install.sh              构建并安装到 ~/Applications
#   ./install.sh --autostart  再注册开机自启
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="NotchDash"

# 优先装到 /Applications：Launchpad、Spotlight 和 Finder 侧边栏的「应用程序」
# 指的都是这里。~/Applications 虽然不需要权限，但侧边栏默认不显示，容易找不到。
# 传 --user 可强制装到用户目录。
if [ "${1:-}" = "--user" ] || [ ! -w /Applications ]; then
  DEST_DIR="$HOME/Applications"
  mkdir -p "$DEST_DIR"
else
  DEST_DIR="/Applications"
fi
DEST="$DEST_DIR/$APP_NAME.app"
PLIST="$HOME/Library/LaunchAgents/app.notchdash.NotchDash.plist"

echo "① 构建"
./build.sh

echo "② 安装到 $DEST"
mkdir -p "$DEST_DIR"
# 正在运行就先停掉，否则复制会失败
pkill -f "$DEST/Contents/MacOS/$APP_NAME" 2>/dev/null || true
rm -rf "$DEST"
cp -R "build/$APP_NAME.app" "$DEST"

if [ "${1:-}" = "--autostart" ] || [ "${2:-}" = "--autostart" ]; then
  echo "③ 注册开机自启"
  mkdir -p "$(dirname "$PLIST")"
  cat > "$PLIST" <<PLIST_EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>app.notchdash.NotchDash</string>
  <key>ProgramArguments</key>
  <array><string>$DEST/Contents/MacOS/$APP_NAME</string></array>
  <key>RunAtLoad</key><true/>
  <!-- 只在异常退出时拉起；从右键菜单正常退出就不再重启 -->
  <key>KeepAlive</key>
  <dict><key>SuccessfulExit</key><false/></dict>
</dict>
</plist>
PLIST_EOF
  launchctl bootout "gui/$UID/app.notchdash.NotchDash" 2>/dev/null || true
  launchctl bootstrap "gui/$UID" "$PLIST"
  echo "   已注册，开机自动启动"
else
  echo "③ 跳过开机自启（要的话加 --autostart）"
  open "$DEST"
fi

echo
echo "✅ 完成。右键点击刘海下方的面板可以刷新、改配置、退出。"
