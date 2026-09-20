# NotchDash

把 Claude Code / Codex 的额度和系统状态，常驻在 MacBook 刘海下方。

![展开态](docs/screenshot-expanded.png)

平时是刘海两侧的两个小数字，鼠标移上去展开完整面板。默认显示**剩余**额度——你真正要决策的是"还能不能继续干活"。

![收起态](docs/screenshot-collapsed.png)

## 先说清楚：刘海本身不会发光

刘海是摄像头模块的物理遮挡，那块区域**没有像素**，不可能在上面显示任何东西。

这类工具的实际做法是：在刘海正下方画一个纯黑窗口，与刘海的黑色无缝拼接，看上去像刘海"变大了"。NotchDash 也是这么做的。

## 功能

- **Claude Code / Codex 额度**：5 小时窗口 + 7 天窗口的已用百分比、重置倒计时，按用量变色
- **系统状态**：CPU、内存、实时网速、电池
- **自定义数据源**：任意 shell 命令的输出都能显示在面板上
- 鼠标悬停展开；展开后右上角 `⋯` 按钮（或在面板上右键）可切换剩余/已用、刷新、改配置、退出
- 自动避让菜单栏图标，不和已有图标抢位置

## 额度数据从哪来

有两条通道，**本地通道永远优先**，失效或过期时才用 API 兜底：

| 工具 | 主通道（本地，零凭据） | 兜底通道（联网） |
|---|---|---|
| Claude Code | statusline 官方负载里的 `rate_limits`（v2.1.6+），由 `scripts/statusline.sh` 落盘 | `api.anthropic.com/api/oauth/usage` |
| Codex | `~/.codex/sessions/**/*.jsonl` 里 `token_count` 事件的 `rate_limits` | `chatgpt.com/backend-api/wham/usage` |

主通道只读本机文件，不碰凭据也不联网，代价是 Claude Code / Codex 没运行时数据不刷新（界面会标"X 分钟前"）。兜底通道用本机已有的登录态直接问官方要，随时可查。

**兜底通道默认开启，可以关掉**（见下方配置）。它用的是未公开端点，官方改动就可能失效——所以它只是兜底。

## 安装

只需要 Command Line Tools，**不用装完整 Xcode**：

```bash
xcode-select --install    # 如果还没装过
git clone <本仓库>
cd minitool
./install.sh              # 构建并安装到 ~/Applications
./install.sh --autostart  # 顺便注册开机自启
```

要让 Claude Code 的额度流进来，还需要把状态栏指向本项目的旁路脚本。编辑 `~/.claude/settings.json`：

```json
{
  "statusLine": {
    "type": "command",
    "command": "/你的路径/minitool/scripts/statusline.sh"
  }
}
```

这个脚本会先抄一份额度数据，再把原始输入转发给下游状态栏程序，**终端里看到的状态栏不受影响**。它会自动探测 claude-hud；想指定别的程序就设环境变量 `NOTCHDASH_DOWNSTREAM`。

> 改之前记得备份原来的 `command` 值。`uninstall.sh` 能自动还原（前提是改动由本项目脚本做的）。

## 面板压住菜单栏图标怎么办

菜单栏图标是从右往左排的，排满右侧后会**跳过刘海在左边继续排**，所以两侧都可能和面板抢地盘。

NotchDash 会自己量：通过辅助功能接口读出每个状态栏图标的坐标，算出刘海左右各剩多少空间，然后挑一种放得下的排布：

| 排布 | 选用条件 |
|---|---|
| 刘海左右分开 | 两侧都放得下（最好看） |
| 全部靠左 | 右侧不够、左侧够 |
| 刘海正下方 | 两侧都不够（不占菜单栏，但会遮住窗口顶部约 21pt） |

这需要给 NotchDash **辅助功能**权限（系统设置 → 隐私与安全性 → 辅助功能）。首次启动会请求一次，拒绝了也能用——只是得自己在 `⋯` 菜单 →「收起态排布」里选一种。

想知道当前量到了多少：

```bash
./build/NotchDash.app/Contents/MacOS/NotchDash --probe-menubar
```

> 注意：从终端跑这条命令时，它继承的是终端的权限；而双击运行的 App 用的是自己的权限，两者可能不一致。App 内部的实际状态写在 `~/.notchdash/status.json`。

## 面板压住菜单栏图标怎么办

菜单栏图标从右往左排，**排满右侧后会跳过刘海、在左边继续排**，所以两侧都可能和面板抢地盘。

NotchDash 会自己量：通过辅助功能接口读出每个状态栏图标的坐标，算出刘海左右各剩多少空间，再挑一种放得下的排布：

| 排布 | 选用条件 |
|---|---|
| 刘海左右分开 | 两侧都放得下（最好看） |
| 全部靠左 | 右侧不够、左侧够 |
| 刘海正下方 | 两侧都不够（不占菜单栏，但会遮住窗口顶部约 21pt） |

这需要给 NotchDash **辅助功能**权限（系统设置 → 隐私与安全性 → 辅助功能）。首次启动会请求一次；拒绝了也能用，只是得自己在 `⋯` 菜单 →「收起态排布」里选一种。

查看当前量到多少：

```bash
./build/NotchDash.app/Contents/MacOS/NotchDash --probe-menubar
```

> 注意：从终端跑这条命令继承的是**终端**的权限，而双击运行的 App 用的是**它自己**的权限，两者可能不一致。App 内部的真实状态写在 `~/.notchdash/status.json`。

## 切换账号后会怎样

| 链路 | 反应 |
|---|---|
| Claude Code（statusline） | **立即**——新账号的数据会覆盖快照 |
| Claude Code（API 兜底） | 最多 5 分钟（限流期间用的是上次结果） |
| Codex | **立即**——见下 |

Codex 的会话日志里**不记录账号**（`session_meta` 只有 session_id、cwd、模型这些），
所以换账号后旧日志照样会被读到，而且只要它足够新鲜就不会触发 API 兜底去纠正。

处理办法是拿 `~/.codex/auth.json` 里的 `account_id` 当锚点：一旦它变了就记下切换
时刻（存在 `~/.notchdash/state.json`），此后只认这个时刻之后写入的会话日志；同时
作废 API 结果缓存、立刻重新请求。所以换完账号立即就是新账号的额度。

## 配置

`~/.notchdash/config.json`（右键菜单 →「打开配置文件」可直接打开，改完 20 秒内生效）：

```json
{
  "oauth_fallback": true,
  "show_remaining": true,
  "custom_sources": [
    { "label": "负载", "command": "sysctl -n vm.loadavg | awk '{print $2}'", "interval": 20 },
    { "label": "未提交", "command": "cd ~/项目 && git status --short | wc -l", "interval": 30 }
  ]
}
```

- `oauth_fallback`：是否允许 API 兜底。设 `false` 就完全不联网、不读凭据
- `show_remaining`：`true` 显示剩余额度，`false` 显示已用额度。菜单里也能直接切换，会写回这里
- `auto_layout`：是否按菜单栏实际占用自动挑排布（需辅助功能权限）
- `collapsed_layout`：`auto_layout` 关掉时用哪种排布——`split` / `left` / `below`
- `auto_layout`：是否按菜单栏实际占用自动挑排布（需辅助功能权限）
- `collapsed_layout`：`auto_layout` 关掉时用哪种排布，`split` / `left` / `below`
  - 不论哪种模式，**颜色始终按已用量算**（越用越红），所以剩余 0% 是红的
- `custom_sources`：每条跑一个命令，取标准输出第一行（最多 24 字符）显示

⚠️ 自定义命令等同于你自己在终端里敲，别放不信任的配置。

## 隐私与安全

- 主通道只读本机文件，不联网
- 兜底通道读取本机已有的登录态（Claude 走钥匙串 `Claude Code-credentials`，Codex 走 `~/.codex/auth.json`），**只发给各自官方域名**，不保存、不落盘、不外传
- 本程序不自己刷新 token，依赖 Claude Code / Codex 自己维护登录态
- 第一次读钥匙串时系统会弹授权框，点「允许」即可；不想授权就把 `oauth_fallback` 设为 `false`

## 适配

刘海尺寸、菜单栏高度、两翼宽度全部运行时实测，没有写死任何机型数字：

- 刘海宽高取自 `NSScreen.safeAreaInsets` 和 `auxiliaryTopLeft/RightArea`
- 收起态两翼宽度由内容实际渲染宽度决定，换字体、换语言、数字变长都不会被裁
- 展开宽度跟随屏幕宽度
- 改分辨率 / 缩放、插拔外接屏、合盖开盖都会重新测量（监听 `didChangeScreenParametersNotification`）
- 接了外接屏时，面板始终画在带刘海的那块屏上
- 没有刘海的机器也能用，会退化成屏幕顶部居中的小面板

## 排查问题

```bash
./build/NotchDash.app/Contents/MacOS/NotchDash --probe
```

不启动界面，直接打印当前采集到的所有数据、数据来源、以及每条通道的失败原因。

只想单独测兜底通道（钥匙串读取、token 有效性、端点连通性）：

```bash
./build/NotchDash.app/Contents/MacOS/NotchDash --probe-oauth
```

界面本身也能自查（不需要屏幕录制权限，App 自己渲染）：

```bash
NOTCHDASH_DEMO=expanded ./build/NotchDash.app/Contents/MacOS/NotchDash --snapshot /tmp/a.png
```

常见情况：

- **Claude Code 一直显示"等待刷新状态栏"** → statusline 没指向 `scripts/statusline.sh`，或该会话还没产生第一次模型响应
- **Codex 显示"已过期"** → 最近没用 Codex，属正常；开着兜底的话会自动走 API。本地数据超过 15 分钟即视为过期，所以不常开 Codex 的话基本都走 API（最短 5 分钟请求一次）
- **面板挡住了菜单栏图标** → 菜单栏图标太多挤到了刘海附近，减少图标或调窄面板

## 退不掉怎么办

面板上右键，或展开后点右上角 `⋯`，选「退出 NotchDash」。实在不行：

```bash
pkill -f NotchDash
```

## 卸载

```bash
./uninstall.sh
```

会停掉进程、删除开机自启、移除 App，并还原 `~/.claude/settings.json` 里的状态栏命令。配置和快照（`~/.notchdash/`）保留，需要的话自己删。

## 技术说明

- Swift + SwiftUI + AppKit，`NSPanel` 置于菜单栏之上（`screenSaverWindow` 层级）
- 刻意**不使用 SwiftUI 宏**（`@State` 等）：Command Line Tools 不带 `SwiftUIMacros` 插件，用了就必须装完整 Xcode 才能编译
- 窗口固定为最大尺寸、内容自适应，展开/收起不 resize 窗口，动画无抖动
