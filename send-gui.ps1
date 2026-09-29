#Requires -Version 5.1
# QQ 群发小工具 —— WinForms 桌面界面，无需命令行
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Net.Http

try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }

$script:DefaultFile = Join-Path $PSScriptRoot 'message.txt'
$script:QuoteFile = Join-Path $PSScriptRoot 'quotes.txt'

# 从同目录 config.json 读取本地敏感配置（token/路径/群号），缺省回退默认值
$script:CfgPath = Join-Path $PSScriptRoot 'config.json'
$script:Cfg = if (Test-Path -LiteralPath $script:CfgPath) {
    Get-Content -LiteralPath $script:CfgPath -Raw -Encoding UTF8 | ConvertFrom-Json
} else { $null }
$script:Api       = if ($script:Cfg) { [string]$script:Cfg.Api }        else { 'http://127.0.0.1:3000' }
$script:Token     = if ($script:Cfg) { [string]$script:Cfg.Token }      else { '' }
$script:NapCatDir = if ($script:Cfg) { [string]$script:Cfg.NapCatDir }  else { '' }
$script:Groups    = if ($script:Cfg -and $script:Cfg.Groups) { @($script:Cfg.Groups) } else { @() }
$script:Launcher  = if ($script:NapCatDir) { Join-Path $script:NapCatDir 'launcher-user.bat' } else { '' }

$script:Quotes = @()
if (Test-Path -LiteralPath $script:QuoteFile) {
    $script:Quotes = Get-Content -LiteralPath $script:QuoteFile -Encoding UTF8 | Where-Object { $_.Trim() }
}

# ---------- 工具函数 ----------
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

function Invoke-OneBot {
    param([Parameter(Mandatory)][string]$Action, [hashtable]$Payload)
    $uri = $script:Api.TrimEnd('/') + '/' + $Action
    $json = if ($Payload) { $Payload | ConvertTo-Json -Compress -Depth 10 } else { '{}' }
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
    $headers = @{}
    if ($script:Token) { $headers['Authorization'] = 'Bearer ' + $script:Token }
    Invoke-RestMethod -Uri $uri -Method Post -Body $bytes `
        -ContentType 'application/json; charset=utf-8' -Headers $headers -TimeoutSec 20
}

# ---------- 控件 ----------
$form = New-Object System.Windows.Forms.Form
$form.Text = 'QQ 群发小工具'
$iconPath = Join-Path $PSScriptRoot 'appicon.ico'
$form.ShowIcon = $true
$form.Icon = if (Test-Path -LiteralPath $iconPath) { New-Object System.Drawing.Icon($iconPath) } else { [System.Drawing.SystemIcons]::Application }
$form.Size = New-Object System.Drawing.Size(760, 680)
$form.StartPosition = 'CenterScreen'
$form.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 9)
$form.MinimumSize = New-Object System.Drawing.Size(660, 580)

$lblStatus = New-Object System.Windows.Forms.Label
$lblStatus.Text = '未连接 NapCat'
$lblStatus.Location = New-Object System.Drawing.Point(15, 12)
$lblStatus.Size = New-Object System.Drawing.Size(600, 22)
$lblStatus.ForeColor = [System.Drawing.Color]::Gray

$grpSend = New-Object System.Windows.Forms.GroupBox
$grpSend.Text = '发送设置'
$grpSend.Location = New-Object System.Drawing.Point(15, 40)
$grpSend.Size = New-Object System.Drawing.Size(715, 95)

$lblGroup = New-Object System.Windows.Forms.Label
$lblGroup.Text = '目标'
$lblGroup.Location = New-Object System.Drawing.Point(15, 30)
$lblGroup.Size = New-Object System.Drawing.Size(60, 22)

$cmbType = New-Object System.Windows.Forms.ComboBox
$cmbType.DropDownStyle = 'DropDownList'
$cmbType.Location = New-Object System.Drawing.Point(85, 27)
$cmbType.Size = New-Object System.Drawing.Size(75, 25)
$cmbType.Items.AddRange(@('群聊', '私聊'))
$cmbType.SelectedIndex = 0

$cmbGroup = New-Object System.Windows.Forms.ComboBox
$cmbGroup.DropDownStyle = 'DropDown'
$cmbGroup.Location = New-Object System.Drawing.Point(170, 27)
$cmbGroup.Size = New-Object System.Drawing.Size(150, 25)
if ($script:Groups.Count -gt 0) {
    $cmbGroup.Items.AddRange([object[]]$script:Groups)
    $cmbGroup.SelectedIndex = 0
} else {
    $cmbGroup.Items.Add('')
}

$lblTimes = New-Object System.Windows.Forms.Label
$lblTimes.Text = '次数'
$lblTimes.Location = New-Object System.Drawing.Point(340, 30)
$lblTimes.Size = New-Object System.Drawing.Size(50, 22)

$numTimes = New-Object System.Windows.Forms.NumericUpDown
$numTimes.Location = New-Object System.Drawing.Point(395, 27)
$numTimes.Size = New-Object System.Drawing.Size(70, 25)
$numTimes.Minimum = 1
$numTimes.Maximum = 1000
$numTimes.Value = 20

$lblJitter = New-Object System.Windows.Forms.Label
$lblJitter.Text = '防风控混杂'
$lblJitter.Location = New-Object System.Drawing.Point(485, 30)
$lblJitter.Size = New-Object System.Drawing.Size(80, 22)

$cmbJitter = New-Object System.Windows.Forms.ComboBox
$cmbJitter.DropDownStyle = 'DropDownList'
$cmbJitter.Location = New-Object System.Drawing.Point(568, 27)
$cmbJitter.Size = New-Object System.Drawing.Size(65, 25)
$cmbJitter.Items.AddRange(@('关闭', '2%', '10%', '20%'))
$cmbJitter.SelectedIndex = 3

$grpSend.Controls.Add($lblGroup)
$grpSend.Controls.Add($cmbType)
$grpSend.Controls.Add($cmbGroup)
$grpSend.Controls.Add($lblTimes)
$grpSend.Controls.Add($numTimes)
$grpSend.Controls.Add($lblJitter)
$grpSend.Controls.Add($cmbJitter)

$grpContent = New-Object System.Windows.Forms.GroupBox
$grpContent.Text = '发送内容（手动输入 / 或从语录选择）'
$grpContent.Location = New-Object System.Drawing.Point(15, 145)
$grpContent.Size = New-Object System.Drawing.Size(715, 215)

$cmbSource = New-Object System.Windows.Forms.ComboBox
$cmbSource.DropDownStyle = 'DropDownList'
$cmbSource.Location = New-Object System.Drawing.Point(10, 22)
$cmbSource.Size = New-Object System.Drawing.Size(695, 25)
$cmbSource.Items.Add('随机抽取语录（默认）')
$cmbSource.Items.Add('手动输入（下方编辑框）')
for ($qi = 0; $qi -lt $script:Quotes.Count; $qi++) {
    $qText = $script:Quotes[$qi]
    if ($qText.Length -gt 26) { $qText = $qText.Substring(0, 26) + '...' }
    $cmbSource.Items.Add(('第{0}句：{1}' -f ($qi + 1), $qText))
}
$cmbSource.SelectedIndex = 0

$txtContent = New-Object System.Windows.Forms.TextBox
$txtContent.Multiline = $true
$txtContent.ScrollBars = 'Vertical'
$txtContent.AcceptsReturn = $true
$txtContent.Location = New-Object System.Drawing.Point(10, 55)
$txtContent.Size = New-Object System.Drawing.Size(695, 150)
$txtContent.WordWrap = $true
if (Test-Path -LiteralPath $script:DefaultFile) {
    $txtContent.Text = (Get-Content -LiteralPath $script:DefaultFile -Raw -Encoding UTF8).Trim()
}
$grpContent.Controls.Add($cmbSource)
$grpContent.Controls.Add($txtContent)

$grpLog = New-Object System.Windows.Forms.GroupBox
$grpLog.Text = '日志'
$grpLog.Location = New-Object System.Drawing.Point(15, 370)
$grpLog.Size = New-Object System.Drawing.Size(715, 200)

$txtLog = New-Object System.Windows.Forms.RichTextBox
$txtLog.Multiline = $true
$txtLog.ReadOnly = $true
$txtLog.BackColor = [System.Drawing.Color]::White
$txtLog.Location = New-Object System.Drawing.Point(10, 22)
$txtLog.Size = New-Object System.Drawing.Size(695, 168)
$txtLog.WordWrap = $true
$grpLog.Controls.Add($txtLog)

$btnLoad = New-Object System.Windows.Forms.Button
$btnLoad.Text = '重新加载内容'
$btnLoad.Location = New-Object System.Drawing.Point(15, 580)
$btnLoad.Size = New-Object System.Drawing.Size(130, 34)

$btnCheck = New-Object System.Windows.Forms.Button
$btnCheck.Text = '检查连接'
$btnCheck.Location = New-Object System.Drawing.Point(155, 580)
$btnCheck.Size = New-Object System.Drawing.Size(110, 34)

$btnSend = New-Object System.Windows.Forms.Button
$btnSend.Text = '发送'
$btnSend.Location = New-Object System.Drawing.Point(275, 580)
$btnSend.Size = New-Object System.Drawing.Size(140, 34)
$btnSend.BackColor = [System.Drawing.Color]::LimeGreen
$btnSend.ForeColor = [System.Drawing.Color]::White
$btnSend.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 10, [System.Drawing.FontStyle]::Bold)

$lblHint = New-Object System.Windows.Forms.Label
$lblHint.Text = '启动时自动拉起 NapCat，登录成功即自动发送'
$lblHint.Location = New-Object System.Drawing.Point(430, 587)
$lblHint.Size = New-Object System.Drawing.Size(300, 22)
$lblHint.ForeColor = [System.Drawing.Color]::Gray

$form.Controls.Add($lblStatus)
$form.Controls.Add($grpSend)
$form.Controls.Add($grpContent)
$form.Controls.Add($grpLog)
$form.Controls.Add($btnLoad)
$form.Controls.Add($btnCheck)
$form.Controls.Add($btnSend)
$form.Controls.Add($lblHint)

# ---------- UI 帮助函数 ----------
function Add-Log {
    param($text, $color)
    $txtLog.SelectionStart = $txtLog.TextLength
    $txtLog.SelectionLength = 0
    if ($color) { $txtLog.SelectionColor = $color }
    $txtLog.AppendText($text + "`r`n")
    $txtLog.ScrollToCaret()
}

function Set-Status {
    param($text, $color)
    $lblStatus.Text = $text
    if ($color) { $lblStatus.ForeColor = $color }
}

function Set-Buttons {
    param($sendEnabled, $checkEnabled)
    $btnSend.Enabled = $sendEnabled
    $btnCheck.Enabled = $checkEnabled
}

# 登录轮询：NapCat 启动后每 3 秒检查一次，登录成功即自动发送
$loginTimer = New-Object System.Windows.Forms.Timer
$loginTimer.Interval = 3000
$loginTimer.Add_Tick({
    try {
        $login = Invoke-OneBot -Action 'get_login_info'
        if ($login -and $login.status -eq 'ok' -and $login.retcode -eq 0) {
            $loginTimer.Stop()
            Set-Status ('登录成功：{0}（{1}）' -f $login.data.nickname, $login.data.user_id) 'Green'
            Add-Log ('登录成功：{0}（{1}），开始自动发送...' -f $login.data.nickname, $login.data.user_id) 'Green'
            Send-Work
        }
    } catch { }
})

# ---------- 检查连接（同步执行，秒级完成） ----------
function Check-Work {
    try {
        Set-Buttons $false $false
        Set-Status '正在连接 NapCat ...' 'Blue'
        Add-Log '正在连接 NapCat ...' 'Black'
        [System.Windows.Forms.Application]::DoEvents()
        $login = Invoke-OneBot -Action 'get_login_info'
        if ($login.status -ne 'ok' -or $login.retcode -ne 0) {
            throw 'NapCat 返回异常：' + ($login | ConvertTo-Json -Compress)
        }
        $botName = $login.data.nickname
        $botUin = $login.data.user_id
        Add-Log ("已连接：{0}（{1}）" -f $botName, $botUin) 'Green'
        $group = [regex]::Match($cmbGroup.Text, '^\d+').Value
        if ($group) {
            try {
                $gi = Invoke-OneBot -Action 'get_group_info' -Payload @{ group_id = $group }
                if ($gi.status -eq 'ok') {
                    Add-Log ("目标群：{0}（{1} 人）" -f $gi.data.group_name, $gi.data.member_count) 'Green'
                }
            } catch {
                Add-Log ("取群信息失败（不影响发送）：{0}" -f $_.Exception.Message) 'Orange'
            }
        }
        Set-Status '连接正常' 'Green'
    } catch {
        Set-Status '连接失败：NapCat 未启动？' 'Red'
        Add-Log ("连接失败：{0}" -f $_.Exception.Message) 'Red'
    } finally {
        Set-Buttons $true $true
    }
}

# ---------- 发送（同步执行，并行请求秒级完成） ----------
function Send-Work {
    $group = [regex]::Match($cmbGroup.Text, '^\d+').Value
    if (-not $group) {
        Add-Log ("群号格式不正确：{0}" -f $cmbGroup.Text) 'Red'
        return
    }
    $mode = $cmbSource.SelectedIndex
    if ($mode -lt 0) { $mode = 0 }
    $baseContent = ''
    $sourceText = ''
    if ($mode -eq 0) {
        if ($script:Quotes.Count -eq 0) {
            Add-Log '语录库为空，请检查 quotes.txt' 'Red'
            return
        }
        $sourceText = '随机语录'
    } elseif ($mode -eq 1) {
        $baseContent = $txtContent.Text.Trim()
        if (-not $baseContent) {
            Add-Log '手动内容为空，请先输入或切换为语录模式' 'Red'
            return
        }
        $sourceText = '手动内容'
    } else {
        $qi = $mode - 2
        if ($qi -lt 0 -or $qi -ge $script:Quotes.Count) {
            Add-Log ('语录序号无效：{0}' -f ($qi + 1)) 'Red'
            return
        }
        $baseContent = $script:Quotes[$qi]
        $sourceText = ('第{0}句' -f ($qi + 1))
    }
    $times = [int]$numTimes.Value
    $jitterPct = @(0, 2, 10, 20)[$cmbJitter.SelectedIndex]
    if ($null -eq $jitterPct -or $jitterPct -lt 0) { $jitterPct = 20 }
    $targetType = $cmbType.SelectedIndex
    if ($targetType -lt 0) { $targetType = 0 }
    $targetWord = if ($targetType -eq 0) { '群' } else { '用户' }
    $apiAction = if ($targetType -eq 0) { 'send_group_msg' } else { 'send_private_msg' }
    $idKey = if ($targetType -eq 0) { 'group_id' } else { 'user_id' }
    try {
        Set-Buttons $false $false
        Set-Status ("发送中：{0} 条 → {1} {2} ..." -f $times, $targetWord, $group) 'Blue'
        Add-Log ("开始发送：{0} 条 → {1} {2}（来源：{3}，{4}）" -f $times, $targetWord, $group, $sourceText, $(if ($jitterPct -gt 0) { ('掺 {0}% 随机符号' -f $jitterPct) } else { '原样' })) 'Black'
        [System.Windows.Forms.Application]::DoEvents()
        $uri = $script:Api.TrimEnd('/') + '/' + $apiAction
        $client = New-Object System.Net.Http.HttpClient
        $client.Timeout = [TimeSpan]::FromSeconds(30)
        if ($script:Token) {
            $client.DefaultRequestHeaders.Authorization = `
                [System.Net.Http.Headers.AuthenticationHeaderValue]::new('Bearer', $script:Token)
        }
        $tasks = @()
        for ($i = 1; $i -le $times; $i++) {
            $msg = $baseContent
            if ($mode -eq 0) { $msg = $script:Quotes[(Get-Random -Maximum $script:Quotes.Count)] }
            if ($jitterPct -gt 0) { $msg = New-JitterText -Text $msg -Ratio ($jitterPct / 100.0) }
            $jsonBody = @{ $idKey = $group; message = $msg } | ConvertTo-Json -Compress -Depth 10
            $c = [System.Net.Http.StringContent]::new($jsonBody, [System.Text.Encoding]::UTF8, 'application/json')
            $tasks += $client.PostAsync($uri, $c)
        }
        [System.Threading.Tasks.Task]::WaitAll($tasks)
        [System.Windows.Forms.Application]::DoEvents()
        $ok = 0; $fail = 0; $failMsg = @()
        for ($i = 1; $i -le $times; $i++) {
            try {
                $resp = $tasks[$i - 1].Result
                $body = $resp.Content.ReadAsStringAsync().Result
                $r = $body | ConvertFrom-Json
                if ($r.status -eq 'ok' -and $r.retcode -eq 0) {
                    $ok++
                } else {
                    $fail++
                    $failMsg += ("第{0}条 retcode={1}" -f $i, $r.retcode)
                }
            } catch {
                $fail++
                $failMsg += ("第{0}条请求异常" -f $i)
            }
        }
        $client.Dispose()
        if ($fail -eq 0) {
            Set-Status ("完成：成功 {0} 条，失败 0 条" -f $ok) 'Green'
            Add-Log ("发送完成：成功 {0} 条，失败 0 条（{1} {2}）" -f $ok, $targetWord, $group) 'Green'
        } else {
            Set-Status ("完成：成功 {0} 条，失败 {1} 条" -f $ok, $fail) 'Red'
            Add-Log ("发送完成：成功 {0} 条，失败 {1} 条（{2} {3}）：{4}" -f $ok, $fail, $targetWord, $group, ($failMsg -join '；')) 'Red'
        }
    } catch {
        Set-Status '发送出错' 'Red'
        Add-Log ('发送出错：' + $_.Exception.Message) 'Red'
    } finally {
        Set-Buttons $true $true
    }
}

# ---------- 自动启动流程：未连接则拉起 NapCat，登录成功后自动发送 ----------
function Auto-Boot {
    Add-Log '=== 自动流程开始 ===' 'Black'
    try {
        $login = Invoke-OneBot -Action 'get_login_info'
        if ($login.status -eq 'ok' -and $login.retcode -eq 0) {
            Add-Log ("已连接：{0}（{1}），开始自动发送..." -f $login.data.nickname, $login.data.user_id) 'Green'
            Send-Work
            return
        }
    } catch { }
    Add-Log '未检测到 NapCat，正在自动启动（会重启 QQ）...' 'Black'
    if (-not (Test-Path -LiteralPath $script:Launcher)) {
        Add-Log ("找不到 NapCat 启动器：{0}`n请手动运行 start-napcat.bat" -f $script:Launcher) 'Red'
        return
    }
    try {
        # 经 cmd.exe 重定向，可静默杀掉已运行的 QQ（即使 QQ 未运行也不会抛"进程未找到"错）
        cmd.exe /c "taskkill /F /IM QQ.exe  2>nul & taskkill /F /IM QQEX.exe 2>nul"
        Set-Status '正在重启 QQ 并启动 NapCat ...' 'Orange'
        Add-Log '已关闭 QQ，正在通过 NapCat 重启 ...' 'Black'
        [System.Windows.Forms.Application]::DoEvents()
        Start-Sleep -Seconds 3
        Start-Process -FilePath 'cmd.exe' -ArgumentList '/c', ('"{0}"' -f $script:Launcher) -WorkingDirectory $script:NapCatDir
        Set-Status '等待 QQ 登录（请扫码确认）...' 'Orange'
        Add-Log 'NapCat 已启动。QQ 窗口弹出后请完成登录（必要时扫码），登录成功将自动发送。' 'Black'
        $loginTimer.Start()
    } catch {
        Add-Log ('启动 NapCat 失败：' + $_.Exception.Message) 'Red'
    }
}

# ---------- 事件 ----------
$btnLoad.Add_Click({
    if (Test-Path -LiteralPath $script:DefaultFile) {
        $txtContent.Text = (Get-Content -LiteralPath $script:DefaultFile -Raw -Encoding UTF8).Trim()
        Add-Log '已从 message.txt 重新加载内容' 'Green'
    } else {
        Add-Log '未找到 message.txt' 'Red'
    }
})
$btnCheck.Add_Click({ Check-Work })
$btnSend.Add_Click({ Send-Work })
$form.Add_Shown({ Auto-Boot })
[void]$form.ShowDialog()
