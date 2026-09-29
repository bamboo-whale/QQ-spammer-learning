<#
.SYNOPSIS
    群通知三连发 —— 通过本机 NapCat (OneBot 11) 向指定 QQ 群连发 N 条相同文字。

.DESCRIPTION
    不用再复制粘贴三次。脚本调用 NapCat 的 HTTP API (send_group_msg)，
    把同一段通知按设定间隔重复发送到指定群。

.EXAMPLE
    .\send-group-notice.ps1 -Message "今晚 8 点群内开会，请准时参加"
    .\send-group-notice.ps1 -Message "全体注意" -Times 3 -IntervalMs 2000
    .\send-group-notice.ps1 -DryRun                 # 只检查连接，不发送
    .\send-group-notice.ps1                        # 读取同目录 message.txt 的内容

.NOTES
    前置条件：先运行 start-napcat.bat 启动 NapCat 并让 QQ 登录成功。
#>
#Requires -Version 5.1
[CmdletBinding()]
param(
    # 要发送的文字。不填则读取脚本同目录下的 message.txt
    [Parameter(Position = 0)]
    [string]$Message,

    # 目标群号（默认来自同目录 config.json）
    [string]$GroupId,

    # 发送类型：group=群聊（GroupId 为群号），private=私聊（GroupId 为 QQ 号）
    [ValidateSet('group', 'private')]
    [string]$Type = 'group',

    # 发送条数
    [ValidateRange(1, 1000)]
    [int]$Times = 20,

    # 防风控混杂比例：0=原样发送，2/10/20=百分比
    [ValidateSet(0, 2, 10, 20)]
    [int]$JitterPercent = 20,

    # 每条之间的间隔（毫秒）。已改为并行发送，此参数仅保留兼容、不再生效
    [ValidateRange(50, 60000)]
    [int]$IntervalMs = 1500,

    # NapCat OneBot HTTP 接口地址（默认来自同目录 config.json）
    [string]$Api,

    # 接口鉴权 token，需与 NapCat 配置里的 token 一致
    [string]$Token,

    # 从指定文件读取消息内容（UTF-8）
    [string]$MessageFile,

    # 只做检查与预览，不真正发送
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }

# 从同目录 config.json 读取本地敏感配置（token/群号/接口地址），缺省时回退默认值
$script:CfgPath = Join-Path $PSScriptRoot 'config.json'
if (Test-Path -LiteralPath $script:CfgPath) {
    $script:Cfg = Get-Content -LiteralPath $script:CfgPath -Raw -Encoding UTF8 | ConvertFrom-Json
} else {
    $script:Cfg = $null
}
if (-not $Api)  { $Api  = if ($script:Cfg) { $script:Cfg.Api }  else { 'http://127.0.0.1:3000' } }
if (-not $Token){ $Token= if ($script:Cfg) { $script:Cfg.Token } else { '' } }
if (-not $GroupId) { $GroupId = if ($script:Cfg) { [string]$script:Cfg.DefaultGroupId } else { '' } }

function Invoke-OneBot {
    param(
        [Parameter(Mandatory)][string]$Action,
        [hashtable]$Payload
    )
    $uri = $Api.TrimEnd('/') + '/' + $Action
    $json = if ($Payload) { $Payload | ConvertTo-Json -Compress -Depth 10 } else { '{}' }
    # 关键：显式转成 UTF-8 字节再发，避免 Windows PowerShell 5.1 把中文压成 Latin-1 乱码
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
    $headers = @{}
    if ($Token) { $headers['Authorization'] = 'Bearer ' + $Token }
    Invoke-RestMethod -Uri $uri -Method Post -Body $bytes `
        -ContentType 'application/json; charset=utf-8' -Headers $headers -TimeoutSec 20
}

function Write-Step($text, $color = 'Cyan') { Write-Host $text -ForegroundColor $color }

# 在原文中均匀插入约 Ratio(默认20%) 的随机符号，原文完整保留，仅用于让每条消息内容不完全相同
function New-JitterText {
    param(
        [Parameter(Mandatory)][string]$Text,
        [double]$Ratio = 0.2
    )
    $alphabet = '~!#$%&*()_+-=[]{}<>|?@￥'
    $len = $Text.Length
    if ($len -lt 1) { return $Text }
    if ($len -lt 6) {
        return $Text + (-join (1..3 | ForEach-Object { $alphabet[(Get-Random -Maximum $alphabet.Length)] }))
    }
    $chunk = 3
    $count = [math]::Max(1, [int]($len * $Ratio / $chunk))
    $sb = New-Object System.Text.StringBuilder
    $pos = 0
    $step = $len / ($count + 1)
    for ($k = 1; $k -le $count; $k++) {
        $cut = [int]($k * $step)
        if ($cut -le $pos) { $cut = $pos + 1 }
        if ($cut -ge $len) { break }
        [void]$sb.Append($Text.Substring($pos, $cut - $pos))
        $junk = -join (1..$chunk | ForEach-Object { $alphabet[(Get-Random -Maximum $alphabet.Length)] })
        [void]$sb.Append($junk)
        $pos = $cut
    }
    [void]$sb.Append($Text.Substring($pos))
    return $sb.ToString()
}

# ---------- 1. 解析消息内容 ----------
if ($MessageFile) {
    if (-not (Test-Path -LiteralPath $MessageFile)) { throw "找不到消息文件：$MessageFile" }
    $Message = (Get-Content -LiteralPath $MessageFile -Raw -Encoding UTF8)
}
if ([string]::IsNullOrWhiteSpace($Message)) {
    $defaultFile = Join-Path $PSScriptRoot 'message.txt'
    if (Test-Path -LiteralPath $defaultFile) {
        $Message = (Get-Content -LiteralPath $defaultFile -Raw -Encoding UTF8)
    }
}
$Message = ($Message -replace "`r`n", "`n").Trim()
if ([string]::IsNullOrWhiteSpace($Message)) {
    throw "消息内容为空。请用 -Message `"要发的话`"，或编辑 $PSScriptRoot\message.txt"
}

# ---------- 2. 连接与登录状态检查 ----------
Write-Step "正在连接 NapCat：$Api"
try {
    $login = Invoke-OneBot -Action 'get_login_info'
} catch {
    throw @"
连不上 NapCat（$Api）。
请先执行： start-napcat.bat   （会重启 QQ 并注入 NapCat，扫码/确认登录后再跑本脚本）
原始错误：$($_.Exception.Message)
"@
}
if ($login.status -ne 'ok' -or $login.retcode -ne 0) {
    throw "NapCat 返回异常：$($login | ConvertTo-Json -Compress)"
}
$botUin  = $login.data.user_id
$botName = $login.data.nickname
Write-Step ("已连接：{0}（{1}）" -f $botName, $botUin) 'Green'

# ---------- 3. 群信息与身份确认（仅群聊模式） ----------
if ($Type -eq 'group') {
$roleText = '未知'
try {
    $gi = Invoke-OneBot -Action 'get_group_info' -Payload @{ group_id = $GroupId }
    if ($gi.status -eq 'ok') {
        Write-Step ("目标群：{0}（{1} 人）" -f $gi.data.group_name, $gi.data.member_count) 'Green'
    }
} catch { Write-Warning "取群信息失败（不影响发送）：$($_.Exception.Message)" }

try {
    $mi = Invoke-OneBot -Action 'get_group_member_info' -Payload @{ group_id = $GroupId; user_id = $botUin }
    if ($mi.status -eq 'ok') {
        switch ($mi.data.role) {
            'owner'  { $roleText = '群主' }
            'admin'  { $roleText = '管理员' }
            default  { $roleText = '普通成员' }
        }
        Write-Step ("本号在该群身份：{0}" -f $roleText)
    }
} catch {
    Write-Warning "取成员身份失败（不影响发送）：$($_.Exception.Message)"
}
} else {
    Write-Step ("目标用户：{0}（私聊）" -f $GroupId) 'Green'
}

# ---------- 4. 预览 ----------
Write-Host ''
Write-Step ('-' * 52) 'DarkGray'
Write-Host ("目标   : {0} {1}" -f $(if ($Type -eq 'private') { '用户' } else { '群' }), $GroupId)
Write-Host ("条数   : {0} 条（并行发送，防风控混杂 {1}%）" -f $Times, $JitterPercent)
Write-Host ("内容   :") -NoNewline; Write-Host ''
$Message -split "`n" | ForEach-Object { Write-Host ("         | " + $_) }
if ($JitterPercent -gt 0) {
    Write-Host ("示例   : " + (New-JitterText -Text $Message -Ratio ($JitterPercent / 100.0))) -ForegroundColor DarkGray
}
Write-Step ('-' * 52) 'DarkGray'
Write-Host ''

if ($DryRun) {
    Write-Step '[DryRun] 仅预览，未发送任何消息。' 'Yellow'
    return
}

# ---------- 5. 发送（并行，同时发出全部请求） ----------
$ok = 0; $fail = 0
$apiAction = if ($Type -eq 'private') { 'send_private_msg' } else { 'send_group_msg' }
$idKey = if ($Type -eq 'private') { 'user_id' } else { 'group_id' }
$uri = $Api.TrimEnd('/') + '/' + $apiAction

Add-Type -AssemblyName System.Net.Http
$client = New-Object System.Net.Http.HttpClient
$client.Timeout = [TimeSpan]::FromSeconds(30)
if ($Token) {
    $client.DefaultRequestHeaders.Authorization = `
        [System.Net.Http.Headers.AuthenticationHeaderValue]::new('Bearer', $Token)
}

Write-Step ("并行发送 {0} 条 ..." -f $Times)
$tasks = @()
for ($i = 1; $i -le $Times; $i++) {
    $jittered = if ($JitterPercent -gt 0) { New-JitterText -Text $Message -Ratio ($JitterPercent / 100.0) } else { $Message }
    $jsonBody = @{ $idKey = $GroupId; message = $jittered } | ConvertTo-Json -Compress -Depth 10
    $content = [System.Net.Http.StringContent]::new($jsonBody, [System.Text.Encoding]::UTF8, 'application/json')
    $tasks += $client.PostAsync($uri, $content)
}
[System.Threading.Tasks.Task]::WaitAll($tasks)

for ($i = 1; $i -le $Times; $i++) {
    try {
        $resp = $tasks[$i - 1].Result
        $body = $resp.Content.ReadAsStringAsync().Result
        $r = $body | ConvertFrom-Json
        if ($r.status -eq 'ok' -and $r.retcode -eq 0) {
            $ok++
            Write-Step ("[{0}/{1}] 发送成功  message_id={2}" -f $i, $Times, $r.data.message_id) 'Green'
        } else {
            $fail++
            Write-Warning ("[{0}/{1}] 发送失败  retcode={2}  {3}" -f $i, $Times, $r.retcode, $r.message)
        }
    } catch {
        $fail++
        Write-Warning ("[{0}/{1}] 请求异常：{2}" -f $i, $Times, $_.Exception.Message)
    }
}
$client.Dispose()

Write-Host ''
Write-Step ("完成：成功 {0} 条，失败 {1} 条。" -f $ok, $fail) $(if ($fail -eq 0) { 'Green' } else { 'Yellow' })
if ($fail -gt 0) { exit 1 }
