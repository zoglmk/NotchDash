# NotchDash

在 MacBook 刘海下方显示 Claude Code / Codex 的额度、系统状态和股票指数。

[English](README.en.md)

## 效果

收起时只在刘海旁显示关键数字，和刘海的黑色连成一片：

![收起态](docs/screenshot-collapsed.png)

鼠标移上去展开完整面板：

![展开态](docs/screenshot-expanded.png)

刘海本身是摄像头模块的物理遮挡，那块区域没有像素，无法显示内容。本工具的做法是在刘海正下方绘制一个纯黑窗口，与刘海的黑色拼接，视觉上像是刘海变大了。

## 功能

- Claude Code 与 Codex 的额度：剩余或已用百分比、重置倒计时，按状态变色。额度耗尽时改为显示恢复时间
- 系统状态：CPU、内存、实时网速
- 股票指数：A 股、港股、美股，按涨跌上色
- 轮播：收起态可在额度与行情之间轮换显示，面板宽度保持不变
- 自动避让：读取菜单栏图标的实际位置，选择不与之重叠的排布方式
- 自定义数据源：显示任意 shell 命令的输出

## 安装

### 下载发布版

从 [Releases](https://github.com/zoglmk/NotchDash/releases) 下载 zip，解压后将 `NotchDash.app` 移入「应用程序」，双击打开。首次打开需要处理系统拦截，见下方常见问题。

### 从源码构建

只需要 Command Line Tools，不必安装完整 Xcode。

```bash
xcode-select --install          # 若尚未安装
git clone https://github.com/zoglmk/NotchDash.git
cd NotchDash
./install.sh                    # 构建并安装到 ~/Applications
./install.sh --autostart        # 同时注册开机自启
```

### 打开之后

不需要任何配置，额度、系统状态和股票指数会直接显示出来。

首次读取额度时，系统可能弹出钥匙串授权窗口，点「允许」即可。程序通过它读取 Claude Code 已有的登录态来查询额度，不会保存或转发（详见数据来源）。

其余选项都在右键菜单里，包括股票指数、轮播、排布方式和显示模式。

### 可选：让 Claude Code 额度走本地通道

默认情况下 Claude Code 的额度通过官方 API 查询，需要钥匙串授权并联网。如果希望完全不联网、也不读取凭据，可以改用 statusline 通道。

Claude Code 会把额度数据放在状态栏（statusline）的输入里，在 `~/.claude/settings.json` 中指向本项目的转发脚本即可取到：

```json
{
  "statusLine": {
    "type": "command",
    "command": "/你的路径/NotchDash/scripts/statusline.sh"
  }
}
```

该脚本会复制一份额度数据供本工具使用，再将原始输入转发给下游程序，因此终端里的状态栏显示不受影响。脚本会自动识别 claude-hud；使用其他程序时设置环境变量 `NOTCHDASH_DOWNSTREAM` 指定。

修改前请备份原有的 `command` 值。若改动由本项目脚本完成，`uninstall.sh` 可自动还原。

两条通道的区别：

| | statusline 通道 | API 通道 |
|---|---|---|
| 是否联网 | 否 | 是 |
| 是否读取凭据 | 否 | 是，读取本机已有登录态 |
| 数据新鲜度 | Claude Code 运行时实时更新 | 随时可查 |
| 需要配置 | 是 | 否 |

两者可以同时启用，此时优先使用 statusline 通道，数据过期后自动切换到 API。

Codex 的额度直接从本地会话日志读取，无需任何配置。

## 常见问题

### 提示「已损坏，无法打开」

本项目未做 Apple 签名和公证（需要每年 99 美元的开发者账号），从网络下载的版本会被 Gatekeeper 拦截。文件本身没有损坏，该提示是 macOS 对未签名应用的统一措辞。

解除方式一，命令行：

```bash
xattr -dr com.apple.quarantine /Applications/NotchDash.app
```

解除方式二，系统设置：

1. 双击应用，在提示框中点「完成」
2. 打开「系统设置」→「隐私与安全性」，向下滚动
3. 在「安全性」一节点击「仍要打开」
4. 再次确认

macOS 15 起，右键点击图标选择「打开」的方式已失效。从源码构建的版本不受影响。

### 自动排布不生效

自动避让需要辅助功能权限，用于读取菜单栏图标的坐标。

1. 首次启动时会弹出授权请求，点击「打开系统设置」
2. 或手动打开「系统设置」→「隐私与安全性」→「辅助功能」
3. 在列表中找到 NotchDash，打开开关
4. 无需重启，20 秒内生效

不授权也可正常使用，只是需要在 `⋯` 菜单的「收起态排布」中手动选择。

更新应用后可能需要重新授权。macOS 通过签名识别应用，替换 `.app` 文件后原有授权可能失效，表现为自动排布停止工作。此时在列表中选中 NotchDash 点击「−」移除，再重新添加即可。若列表中出现两个 NotchDash，删除旧的那个。

当前权限状态可查看 `~/.notchdash/status.json` 中的 `accessibility_authorized` 字段。

### Claude Code 显示「等待刷新状态栏」

说明两条通道都没取到数据。逐项检查：

- 若关闭了 `oauth_fallback`，则必须配置 statusline，见安装章节
- 若开着 API 兜底，运行 `NotchDash --probe-oauth` 查看失败原因，通常是钥匙串授权被拒绝或登录态已过期，重新登录 Claude Code 即可
- 若已配置 statusline，该提示也可能表示当前会话尚未产生第一次模型响应

### 额度显示「未开始」

限额窗口是滚动的，要等本周期内第一次请求发出才起算，不是每隔固定时间重置一次。窗口尚未开始时，服务端返回的重置时间是「此刻加上完整窗口长度」的占位值，会跟着当前时间一起往后走，这时显示倒计时没有意义，因此标记为「未开始」。

发出第一条消息后窗口才开始计时，倒计时随之固定下来。

### Codex 显示「已过期」

最近未使用 Codex 属于正常现象。本地数据超过 15 分钟视为过期，开启 API 兜底时会自动切换。

### 面板遮挡菜单栏图标

菜单栏图标从右向左排列，右侧排满后会跳过刘海在左侧继续排列，因此两侧都可能与面板冲突。开启辅助功能权限后，程序会测量两侧剩余空间并自动选择排布：

| 排布 | 选用条件 |
|---|---|
| 全部靠左 | 左侧空间够 |
| 刘海正下方 | 左侧不够。不占用菜单栏，但会遮住窗口顶部约 21pt |

也可在菜单中手动指定。

### 如何退出

在面板上右键，或展开后点击右上角 `⋯`，选择「退出 NotchDash」。也可执行 `pkill -f NotchDash`。

## 配置

大部分选项可在右键菜单中调整，包括显示模式、轮播、股票指数、涨跌配色和排布方式。配置文件位于 `~/.notchdash/config.json`，修改后 20 秒内生效。

```json
{
  "oauth_fallback": true,
  "show_remaining": true,
  "carousel": true,
  "carousel_interval": 10,
  "red_up": true,
  "auto_layout": true,
  "collapsed_layout": "left",
  "stocks": {
    "interval": 60,
    "items": [
      { "label": "上证", "code": "s_sh000001" },
      { "label": "纳指", "code": "gb_ixic" }
    ]
  },
  "custom_sources": [
    { "label": "负载", "command": "sysctl -n vm.loadavg | awk '{print $2}'", "interval": 20 }
  ]
}
```

| 字段 | 说明 |
|---|---|
| `oauth_fallback` | 是否允许 API 兜底。设为 `false` 则完全不联网、不读取凭据 |
| `show_remaining` | `true` 显示剩余额度，`false` 显示已用额度 |
| `carousel` / `carousel_interval` | 轮播开关与间隔，单位秒，最小 2 |
| `red_up` | `true` 为红涨绿跌，`false` 为绿涨红跌。对行情和自定义数据源同时生效 |
| `auto_layout` | 是否根据菜单栏占用自动选择排布，需要辅助功能权限 |
| `collapsed_layout` | 关闭自动排布时使用的方式：`left` / `below` |

无论显示剩余还是已用，颜色始终按已用比例计算，剩余低于 30% 转为红色。

### 股票指数

在右键菜单的「行情」中勾选常用指数，或通过「添加代码」输入个股代码，名称会自动获取。刷新频率可选 10 秒至 5 分钟。

同一菜单下的「涨跌配色」可切换红涨绿跌（A 股习惯）与绿涨红跌（美股习惯），对行情和自定义数据源同时生效。

预设包含上证指数、深证成指、创业板指、沪深 300、恒生指数、道琼斯、纳斯达克、标普 500。

也可直接编辑配置文件。常用代码：

| 代码 | 标的 | 代码 | 标的 |
|---|---|---|---|
| `s_sh000001` | 上证指数 | `gb_dji` | 道琼斯 |
| `s_sz399001` | 深证成指 | `gb_ixic` | 纳斯达克 |
| `s_sz399006` | 创业板指 | `gb_inx` | 标普 500 |
| `s_sh000300` | 沪深 300 | `int_hangseng` | 恒生指数 |

个股直接填写代码，如 `sh600519`、`sz000001`。

数据来自新浪财经公开接口，无需 API Key。交易时段内为行情快照，免费接口通常有秒级到分钟级延迟，加上轮询间隔属于准实时。非交易时段显示最近一次收盘数据。

### 自定义数据源

每条配置执行一个 shell 命令，取标准输出的第一行显示，最多 24 个字符。单条命令超过 5 秒会被终止。输出中包含带符号的百分比时会按涨跌上色。

命令以当前用户身份执行，请勿使用来源不明的配置。

## 数据来源

额度数据有两条通道，本地通道优先，失效或过期时才使用 API。Claude Code 的本地通道需要配置 statusline（见安装），未配置时直接走 API：

| 工具 | 本地通道 | API 兜底 |
|---|---|---|
| Claude Code | statusline 负载中的 `rate_limits`（v2.1.6+） | `api.anthropic.com/api/oauth/usage` |
| Codex | `~/.codex/sessions/**/*.jsonl` 中 `token_count` 事件的 `rate_limits` | `chatgpt.com/backend-api/wham/usage` |

本地通道只读取本机文件，不涉及凭据也不联网，代价是相关程序未运行时数据不再更新，界面会标注最后更新时间。

API 兜底使用本机已有的登录态（Claude 读取钥匙串条目 `Claude Code-credentials`，Codex 读取 `~/.codex/auth.json`），仅发送至各自的官方域名，不保存、不落盘、不转发。本程序不刷新 token，登录态由 Claude Code 和 Codex 自行维护。

兜底通道依赖未公开的接口，官方调整后可能失效，因此仅作为备用。可通过 `oauth_fallback` 关闭。

切换账号后，Claude Code 的 statusline 通道立即反映新账号；API 兜底最多滞后一个限流周期（5 分钟）。Codex 的会话日志不记录账号信息，程序以 `~/.codex/auth.json` 中的 `account_id` 为准，检测到变化时只采用切换之后写入的日志，并立即重新请求 API。

## 兼容性

刘海尺寸、菜单栏高度和面板宽度均在运行时测量，未写死任何机型参数。

- 刘海尺寸取自 `NSScreen.safeAreaInsets` 与 `auxiliaryTopLeftArea` / `auxiliaryTopRightArea`
- 收起态宽度由内容的实际渲染宽度决定，更换字体、语言或数字位数变化都不会被裁切
- 分辨率与缩放变更、外接显示器插拔、开合盖时会重新测量
- 连接外接显示器时，面板始终显示在带刘海的屏幕上
- 无刘海的机型可以使用，面板显示在屏幕顶部居中位置

要求 macOS 13 或更高版本。

## 调试

```bash
NotchDash --probe           # 打印所有数据源的当前状态与失败原因
NotchDash --probe-oauth     # 仅测试 API 兜底通道
NotchDash --probe-menubar   # 打印菜单栏可用空间与排布判断
```

界面可自行渲染为图片，不需要屏幕录制权限：

```bash
NOTCHDASH_DEMO=expanded NotchDash --snapshot /tmp/a.png
```

运行状态写入 `~/.notchdash/status.json`。

从终端执行这些命令时继承的是终端的权限，与双击运行的应用可能不同。

## 卸载

```bash
./uninstall.sh
```

停止进程、移除开机自启和应用，并还原 `~/.claude/settings.json` 中的状态栏配置。配置与缓存目录 `~/.notchdash/` 会保留。

## 实现说明

Swift + SwiftUI + AppKit，使用置于菜单栏层级之上的 `NSPanel`。

未使用 SwiftUI 宏（`@State` 等），因为 Command Line Tools 不包含 `SwiftUIMacros` 插件，使用后必须安装完整 Xcode 才能编译。

窗口保持最大尺寸不变，由内容控制实际绘制区域，展开与收起不触发窗口尺寸变更。

## 许可

MIT
