# 配置与进阶

[← 返回 README](../README.md)

大部分选项在右键菜单里就能调，这份文档是给想深入的人看的。

## 配置文件

位于 `~/.notchdash/config.json`，修改后 20 秒内生效。

```json
{
  "oauth_fallback": true,
  "show_remaining": true,
  "carousel": true,
  "carousel_interval": 10,
  "red_up": true,
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
| `collapsed_layout` | 收起态排布：`left` 全部靠左（默认） / `below` 刘海正下方 |

无论显示剩余还是已用，颜色始终按已用比例计算，剩余低于 30% 转为红色。

## 股票指数

在右键菜单的「行情」中勾选常用指数，或通过「添加代码」输入个股代码，名称会自动获取。刷新频率可选 10 秒至 5 分钟。预设包含上证指数、深证成指、创业板指、沪深 300、恒生指数、道琼斯、纳斯达克、标普 500。

也可直接编辑配置文件。常用代码：

| 代码 | 标的 | 代码 | 标的 |
|---|---|---|---|
| `s_sh000001` | 上证指数 | `gb_dji` | 道琼斯 |
| `s_sz399001` | 深证成指 | `gb_ixic` | 纳斯达克 |
| `s_sz399006` | 创业板指 | `gb_inx` | 标普 500 |
| `s_sh000300` | 沪深 300 | `int_hangseng` | 恒生指数 |

个股直接填写代码，如 `sh600519`、`sz000001`。

数据来自新浪财经公开接口，无需 API Key。交易时段内为行情快照，免费接口通常有秒级到分钟级延迟，加上轮询间隔属于准实时。非交易时段显示最近一次收盘数据。

展开态的底部会按面板宽度自动换行，屏幕宽的一行多排几个，最多三行。

## 自定义数据源

每条配置执行一个 shell 命令，取标准输出的第一行显示，最多 24 个字符。单条命令超过 5 秒会被终止。输出中包含带符号的百分比时会按涨跌上色。

命令以当前用户身份执行，请勿使用来源不明的配置。

## 让 Claude Code 额度走本地通道

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

两者可以同时启用，此时优先使用 statusline 通道，数据过期后自动切换到 API。Codex 的额度直接从本地会话日志读取，无需任何配置。

## 数据来源

| 工具 | 本地通道 | API 兜底 |
|---|---|---|
| Claude Code | statusline 负载中的 `rate_limits`（v2.1.6+） | `api.anthropic.com/api/oauth/usage` |
| Codex | `~/.codex/sessions/**/*.jsonl` 中 `token_count` 事件的 `rate_limits` | `chatgpt.com/backend-api/wham/usage` |

本地通道只读取本机文件，不涉及凭据也不联网，代价是相关程序未运行时数据不再更新，界面会标注最后更新时间。

API 兜底使用本机已有的登录态（Claude 读取钥匙串条目 `Claude Code-credentials`，Codex 读取 `~/.codex/auth.json`），仅发送至各自的官方域名，不保存、不落盘、不转发。本程序不刷新 token，登录态由 Claude Code 和 Codex 自行维护。

兜底通道依赖未公开的接口，官方调整后可能失效，因此仅作为备用。可通过 `oauth_fallback` 关闭。

切换账号后，Claude Code 的 statusline 通道立即反映新账号；API 兜底最多滞后一个限流周期。Codex 的会话日志不记录账号信息，程序以 `~/.codex/auth.json` 中的 `account_id` 为准，检测到变化时只采用切换之后写入的日志，并立即重新请求 API。退出登录后 `auth.json` 会被删除，此时显示「未登录 Codex」，不再沿用上一个账号的数据。

没装 Claude Code 或 Codex 时，对应的那一项不会出现。两个都没装时收起态改为显示 CPU 和内存。

## 几种状态的含义

**额度显示「未开始」**：限额窗口是滚动的，要等本周期内第一次请求发出才起算，不是每隔固定时间重置一次。窗口尚未开始时，服务端返回的重置时间是「此刻加上完整窗口长度」的占位值，会跟着当前时间一起往后走，这时显示倒计时没有意义。发出第一条消息后窗口才开始计时，倒计时随之固定下来。

**Codex 显示「已过期」**：最近未使用 Codex 属于正常现象。本地数据超过 15 分钟视为过期，开启 API 兜底时会自动切换。

**额度用尽时显示时间而不是百分比**：已用超过 99.5% 时，比起「还剩 0%」，「多久以后恢复」更有用。

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
```

界面可自行渲染为图片，不需要屏幕录制权限：

```bash
NOTCHDASH_DEMO=expanded NotchDash --snapshot /tmp/a.png
```

运行状态写入 `~/.notchdash/status.json`。

还有几个用来复现特定环境的开关，正常使用不需要：

```bash
NOTCHDASH_SIMULATE=no-quota      # 假装没装 Claude Code 和 Codex
NOTCHDASH_SIMULATE=codex-logout  # 假装 Codex 已登出
NOTCHDASH_SIMULATE=empty-quota   # 假装装了但取不到额度数据
NOTCHDASH_FAKE="35,25"           # 把两个额度的剩余百分比写死，用来验收配色
```

## 实现说明

Swift + SwiftUI + AppKit，使用置于菜单栏层级之上的 `NSPanel`。

未使用 SwiftUI 宏（`@State` 等），因为 Command Line Tools 不包含 `SwiftUIMacros` 插件，使用后必须安装完整 Xcode 才能编译。

窗口保持最大尺寸不变，由内容控制实际绘制区域，展开与收起不触发窗口尺寸变更。

刘海本身是摄像头模块的物理遮挡，那块区域没有像素。本工具在刘海正下方绘制一个纯黑窗口，与刘海的黑色拼接，视觉上像是刘海变大了。
