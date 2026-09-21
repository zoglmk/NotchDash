#!/bin/bash
# 打一个可分发的压缩包
#   ./release.sh 0.2.0
set -euo pipefail
cd "$(dirname "$0")"

VERSION="${1:-0.2.0}"
OUT="dist"
APP_NAME="NotchDash"

echo "① 构建 v$VERSION"
./build.sh

echo "② 打包"
rm -rf "$OUT"
mkdir -p "$OUT"
# 用 ditto 而不是 zip：能保住 .app 的符号链接和扩展属性
ditto -c -k --sequesterRsrc --keepParent \
      "build/$APP_NAME.app" "$OUT/$APP_NAME-$VERSION.zip"

cd "$OUT"
shasum -a 256 "$APP_NAME-$VERSION.zip" > "$APP_NAME-$VERSION.zip.sha256"
cd ..

# 打包完就清掉构建产物，理由同 install.sh：留着会让 Spotlight 搜出
# 两个同名 App，分不清哪个是装好在跑的那份
rm -rf "build/$APP_NAME.app"

SIZE=$(du -h "$OUT/$APP_NAME-$VERSION.zip" | cut -f1)
echo
echo "✅ $OUT/$APP_NAME-$VERSION.zip  ($SIZE)"
echo "   $(cat "$OUT/$APP_NAME-$VERSION.zip.sha256")"
echo
cat <<NOTE
下一步：把 zip 和 sha256 一起传到 GitHub Release。

⚠️ 这个包没有 Apple 签名和公证，别人下载后会被 Gatekeeper 拦下。
   Release 说明里必须写上解除隔离的命令，否则对方只会看到
   「已损坏，无法打开」这种误导性的提示：

     xattr -dr com.apple.quarantine /Applications/NotchDash.app

   要彻底免掉这一步，得有 Apple 开发者账号（99 美元/年）做签名和公证。
NOTE
