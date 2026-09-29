# QQ 群发小工具

通过本机 [NapCat](https://napcat.app/)（OneBot 11）向指定 QQ 群 / 用户批量发送消息的 PowerShell 工具，带一个 WinForms 桌面界面，无需命令行。

> 声明：本工具本质是高频批量发消息。**正式使用有账号风控风险（警告/限制/封禁），请仅在你自己的测试群、且知晓后果的前提下使用。** 请勿用于骚扰他人。

## 架构

```
send-gui.ps1 / send-group-notice.ps1  →  HTTP POST  →  NapCat (127.0.0.1:3000)  →  你的 QQ  →  群 / 私聊
```

- **GUI 小工具**：`send-gui.ps1`，启动时自动拉起 NapCat，登录成功即按当前设置自动发送。
- **命令行脚本**：`send-group-notice.ps1`，适合脚本化 / 手动控制。
- 发送为**并行**请求，秒级完成；每条可掺约 2% / 10% / 20% 随机符号，使各条内容不完全相同，降低「短时间内重复相同内容」的风控概率。

## 快速开始

### 前置条件

- Windows + PowerShell 5.1
- 已装好 NapCat，并能启动注入到 QQ；NapCat 的 OneBot HTTP 服务已被脚本访问

### 1. 配置（重要）

复制一份 `config.example.json` 为 `config.json`（`config.json` 已加入 `.gitignore`，**不要提交**），填入你自己的值：

| 字段 | 含义 |
|---|---|
| `Api` | NapCat HTTP 地址，默认 `http://127.0.0.1:3000` |
| `Token` | 接口鉴权 token，需与 NapCat 配置一致 |
| `NapCatDir` | NapCat 安装目录（含 `launcher-user.bat` 的那个） |
| `DefaultGroupId` | 默认目标群号（脚本未指定 `-GroupId` 时使用） |
| `Groups` | 桌面工具下拉框里展示的群列表 `["群号 (群名)", ...]` |

> `message.txt`（要发的文字）和 `quotes.txt`（语录库）同样不入库，按需自建。

### 2. 启动桌面工具

双击 `start-tool.bat`（或直接 `powershell -File send-gui.ps1`）。工具会：
1. 自动关闭已有 QQ 并通过 NapCat 重启（NapCat 需在 QQ 启动时注入）
2. 等待登录（必要时扫码）
3. 登录成功即按界面设置自动发送

### 3. 使用命令行脚本

```powershell
# 自检（不发送，只验证连接）
powershell -ExecutionPolicy Bypass -File "send-group-notice.ps1" -DryRun

# 给默认群发一条
powershell -ExecutionPolicy Bypass -File "send-group-notice.ps1" -Message "你好"

# 给指定群发 5 条、掺 2% 符号
powershell -ExecutionPolicy Bypass -File "send-group-notice.ps1" -GroupId 123456789 -Times 5 -JitterPercent 2

# 发给单个用户（私聊，参数为对方 QQ 号）
powershell -ExecutionPolicy Bypass -File "send-group-notice.ps1" -Type private -GroupId 10001 -Times 3
```

## 参数

| 参数 | 默认 | 说明 |
|---|---|---|
| `-Message` | config 缺省 | 要发的文字；留空读 `message.txt` |
| `-MessageFile` | 空 | 从指定 UTF-8 文件读内容 |
| `-Type` | `group` | `group` 群聊 / `private` 私聊 |
| `-GroupId` | config | 群号或私聊对象 QQ 号 |
| `-Times` | `20` | 发送条数（1–1000） |
| `-JitterPercent` | `20` | 掺入随机符号比例：`0/2/10/20` |
| `-IntervalMs` | `1500` | （兼容保留）发送已并行，不再生效 |
| `-Api` | config | NapCat HTTP 地址 |
| `-Token` | config | 接口 token |
| `-DryRun` | 关 | 只检查预览，不发送 |

## 注意事项

- **风控**：并行刷屏本身就有风险。`-Times` 上限 1000、`-JitterPercent` 提供了混淆，但都不能保证不触发腾讯风控（实测超量私聊会被大量拦截 `retcode=200`）。测试群随便，正式群 / 真实对象慎用。
- **编码**：脚本按 UTF-8 发送，`.ps1` 存为 UTF-8 with BOM，PowerShell 5.1 下不会乱码。
- **Token 一致性**：改动 token 需同步改 NapCat 配置与 `config.json`。

## 文件说明

| 文件 | 说明 |
|---|---|
| `send-gui.ps1` | 桌面 GUI 小工具 |
| `send-group-notice.ps1` | 命令行发送脚本 |
| `stop-flow`…（无） | — |
| `config.example.json` | 配置模板（复制为 `config.json`） |
| `start-tool.bat` | GUI 启动入口 |
| `start-napcat.bat` | 手动启动 NapCat 入口 |

`config.json`、`message.txt`、`quotes.txt`、`*.exe`、`*.ico`、`*.log` 均已 `.gitignore`，不会入库。