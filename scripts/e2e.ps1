#requires -Version 7.4
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$AgentRoot,
    [Parameter(Mandatory)][string]$RelayRoot,
    [Parameter(Mandatory)][string]$AndroidRoot,
    [Parameter(Mandatory)][string]$SdkRoot,
    [Parameter(Mandatory)][ValidatePattern('^emulator-\d+$')][string]$PhoneSerial,
    [Parameter(Mandatory)][ValidatePattern('^emulator-\d+$')][string]$WearSerial,
    [ValidateSet('direct','paired')][string]$WearMode = 'direct',
    [Parameter(Mandatory)][string]$OutputDir,
    [switch]$DebugRust,
    [switch]$SkipDesktop,
    [string]$RelayExe
)

$ErrorActionPreference = 'Stop'
$package = 'io.github.jerryskywalker.ainotify.dev'
$namespace = 'io.github.jerryskywalker.ainotify'
. (Join-Path $PSScriptRoot 'phone-inbox-ci.ps1')
$adb = Join-Path $SdkRoot 'platform-tools/adb.exe'
$profile = if ($DebugRust) { 'debug' } else { 'release' }
$agentExe = Join-Path $AgentRoot "target/$profile/ai-notify-agent.exe"
$desktopExe = Join-Path $AgentRoot "target/$profile/ai-notify-desktop.exe"
if (-not $RelayExe) { $RelayExe = Join-Path $RelayRoot "target/$profile/ai-notify-relay.exe" }
$phoneApk = Join-Path $AndroidRoot 'mobile/build/outputs/apk/debug/mobile-debug.apk'
$wearApk = Join-Path $AndroidRoot 'wear/build/outputs/apk/debug/wear-debug.apk'
foreach ($file in @($adb,$agentExe,$relayExe,$phoneApk,$wearApk)) {
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { throw "Missing CI input $file" }
}
if ($PhoneSerial -eq $WearSerial) { throw 'Phone and watch must be distinct AVDs.' }

function Invoke-CheckedAdb([string]$Serial, [string[]]$Arguments) {
    $output = & $adb -s $Serial @Arguments
    if ($LASTEXITCODE) { throw "ADB failed for $Serial ($($Arguments[0])). " }
    $output
}

function Invoke-ProcessInput([string]$Exe, [string[]]$Arguments, [string]$InputString, [switch]$AllowFailure) {
    $info = [Diagnostics.ProcessStartInfo]::new($Exe)
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardInput = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $info.StandardInputEncoding = [Text.UTF8Encoding]::new($false)
    $info.StandardOutputEncoding = [Text.UTF8Encoding]::new($false)
    foreach ($argument in $Arguments) { $info.ArgumentList.Add($argument) }
    $child = [Diagnostics.Process]::Start($info)
    try {
        $stdout = $child.StandardOutput.ReadToEndAsync()
        $stderr = $child.StandardError.ReadToEndAsync()
        $child.StandardInput.Write($InputString)
        $child.StandardInput.Close()
        if (-not $child.WaitForExit(25000)) { $child.Kill(); throw "Timed out running $([IO.Path]::GetFileName($Exe))." }
        $result = [pscustomobject]@{ ExitCode = $child.ExitCode; Output = $stdout.GetAwaiter().GetResult() }
        if ($result.ExitCode -and -not $AllowFailure) {
            throw "$([IO.Path]::GetFileName($Exe)) failed: $($stderr.GetAwaiter().GetResult().Trim())"
        }
        $result
    } finally {
        $child.Dispose()
    }
}

function Wait-For([scriptblock]$Check, [string]$Label, [int]$Seconds = 30) {
    $end = [DateTime]::UtcNow.AddSeconds($Seconds)
    do {
        $result = & $Check
        if ($result) { return $result }
        Start-Sleep -Milliseconds 500
    } while ([DateTime]::UtcNow -lt $end)
    throw "Timed out: $Label"
}

function Get-TestRelayPort {
    $listener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, 0)
    $listener.Start()
    try { $listener.LocalEndpoint.Port } finally { $listener.Stop() }
}

function Start-TestRelay(
    [string]$RelayUrl = $url,
    [hashtable]$RelayEnvironment = $childEnvironment,
    [string]$LogPrefix = 'relay'
) {
    $arguments = @{
        FilePath = $relayExe
        Environment = $RelayEnvironment
        PassThru = $true
        WindowStyle = 'Hidden'
        RedirectStandardOutput = (Join-Path $OutputDir "$LogPrefix.stdout.log")
        RedirectStandardError = (Join-Path $OutputDir "$LogPrefix.stderr.log")
    }
    $process = Start-Process @arguments
    try {
        $null = Wait-For {
            if ($process.HasExited) { throw 'Relay exited during startup.' }
            try { (Invoke-RestMethod -NoProxy "$RelayUrl/healthz" -TimeoutSec 2).ok } catch { }
        } 'relay health'
        $process
    } catch {
        if (-not $process.HasExited) { Stop-Process -Id $process.Id }
        throw
    }
}

function Stop-TestRelay($Process) {
    if ($Process -and -not $Process.HasExited) {
        Stop-Process -Id $Process.Id
        $null = $Process.WaitForExit(5000)
    }
}

function Set-AvdRelay([string]$Serial, [string]$Profile, [int]$RelayPort, [string]$Credential) {
    $settings = @{relay="http://10.0.2.2:$RelayPort";token=$Credential} | ConvertTo-Json -Compress
    $null = Invoke-ProcessInput $adb @('-s',$Serial,'shell','-T',"run-as $package sh -c 'mkdir -p files && cat > files/$Profile-settings.json'") $settings
}

function Prepare-Avd([string]$Serial, [string]$Apk, [string]$Flavor, [bool]$Direct) {
    $null = Invoke-CheckedAdb $Serial @('shell','svc','power','stayon','true')
    $null = Invoke-CheckedAdb $Serial @('shell','input','keyevent','KEYCODE_WAKEUP')
    $null = Invoke-CheckedAdb $Serial @('shell','wm','dismiss-keyguard')
    $null = Invoke-CheckedAdb $Serial @('shell','locksettings','set-disabled','true')
    $null = Invoke-CheckedAdb $Serial @('shell','settings','put','global','cached_apps_freezer','disabled')
    $null = Invoke-CheckedAdb $Serial @('shell','settings','put','secure','spell_checker_enabled','0')
    $null = Invoke-CheckedAdb $Serial @('install','-r',$Apk)
    # CI owns the .dev application data on explicitly selected emulators.
    $null = Invoke-CheckedAdb $Serial @('shell','pm','clear',$package)
    $null = Invoke-CheckedAdb $Serial @('shell','cmd','package','compile','-m','speed',$package)
    $null = Invoke-CheckedAdb $Serial @('shell','pm','grant',$package,'android.permission.POST_NOTIFICATIONS')
    $null = Invoke-CheckedAdb $Serial @('shell','cmd','deviceidle','whitelist',"+$package")
    if ($Flavor -eq 'mobile') {
        $null = Invoke-CheckedAdb $Serial @('shell','cmd','locale','set-app-locales',$package,'--locales','en')
    }
    if ($Direct) {
        $credential = if ($Flavor -eq 'mobile') { $inboxToken } else { $reader }
        $settingsName = if ($Flavor -eq 'mobile') { 'phone' } else { 'wear' }
        Set-AvdRelay $Serial $settingsName $port $credential
    }
    if ($Direct -or $Flavor -eq 'mobile') {
        $null = Invoke-CheckedAdb $Serial @('shell','am','start','-W','-n',"$package/$namespace.$Flavor.MainActivity",'--ez','ainotify_start','true')
    }
}

function Test-Notification([string]$Serial, [string]$Id) {
    $records = Invoke-CheckedAdb $Serial @('shell','cmd','notification','list')
    [bool]($records | Where-Object { $_.Contains("|$package|") -and $_.Contains("|$Id|") } | Select-Object -First 1)
}

function Get-Ui([string]$Serial) {
    for ($i = 0; $i -lt 5; $i++) {
        $dump = & $adb -s $Serial shell uiautomator dump /sdcard/ainotify-ci.xml 2>&1
        $raw = & $adb -s $Serial exec-out cat /sdcard/ainotify-ci.xml 2>$null
        $text = ($raw -join [Environment]::NewLine).Trim()
        if ($text -and $text -match '^<\?xml.*</hierarchy>$') {
            try { return [xml]$text } catch { }
        }
        & $adb -s $Serial shell input keyevent KEYCODE_WAKEUP 2>$null | Out-Null
        Start-Sleep -Milliseconds 400
    }
    throw "Failed to dump UI on $Serial ($dump)"
}

function Save-Screenshot([string]$Serial, [string]$Name) {
    $file = Join-Path $OutputDir $Name
    & $adb -s $Serial exec-out screencap -p > $file
    if ($LASTEXITCODE -or (Get-Item -LiteralPath $file).Length -lt 128) { throw "Screenshot failed on $Serial" }
}

function Test-PairedRelaySwitch {
    $saved = Invoke-CheckedAdb $WearSerial @('shell','run-as',$package,'cat','files/wear-inbox.json')
    $oldCursor = ($saved -join '' | ConvertFrom-Json).cursor
    if ($oldCursor -le 1) { throw 'The paired watch needs a cursor above the new relay first sequence.' }

    $newPort = Get-TestRelayPort
    $newUrl = "http://127.0.0.1:$newPort"
    $newEnvironment = $childEnvironment.Clone()
    $newEnvironment.AINOTIFY_LISTEN = "127.0.0.1:$newPort"
    $newEnvironment.AINOTIFY_DB = Join-Path $scratch 'paired-switch.sqlite3'
    $newRelay = Start-TestRelay $newUrl $newEnvironment 'paired-switch-relay'
    try {
        $empty = Invoke-RestMethod -NoProxy "$newUrl/v1/events" -Headers $readHeaders
        if ($empty.events.Count -ne 0 -or $empty.next_cursor -ne 0) { throw 'Replacement relay must start empty.' }

        $null = Invoke-CheckedAdb $PhoneSerial @('shell','am','force-stop',$package)
        Set-AvdRelay $PhoneSerial 'phone' $newPort $inboxToken
        $null = Invoke-CheckedAdb $PhoneSerial @('shell','am','start','-W','-n',"$package/$namespace.mobile.MainActivity",'--ez','ainotify_start','true')
        Start-Sleep -Seconds 4
        $null = Invoke-CheckedAdb $PhoneSerial @('shell','input','keyevent','KEYCODE_HOME')
        $null = Invoke-CheckedAdb $WearSerial @('shell','input','keyevent','KEYCODE_WAKEUP')

        $id = [Guid]::NewGuid().ToString()
        $preview = 'First reply from the replacement relay'
        $event = @{
            schema_version = 1; id = $id; tool = 'manual'; kind = 'test'; device_name = 'CI-Relay-Switch'
            occurred_at_ms = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds(); message = $preview
        } | ConvertTo-Json -Compress
        $created = Invoke-RestMethod -NoProxy "$newUrl/v1/events" -Method Post `
            -Headers @{Authorization="Bearer $($writers.win)"} -ContentType 'application/json' -Body $event
        if ($created.seq -ne 1) { throw 'Expected the first replacement relay event at sequence 1.' }
        $null = Wait-For { Test-Notification $PhoneSerial $id } 'replacement relay first event on phone'
        "PASS: Phone received replacement relay sequence 1 (previous watch cursor: $oldCursor)"
        $null = Wait-For { & $adb -s $WearSerial shell input keyevent KEYCODE_WAKEUP 2>$null | Out-Null; Test-Notification $WearSerial $id } 'replacement relay first event on paired watch' 90
        $null = Invoke-CheckedAdb $WearSerial @('shell','am','start','-W','-n',"$package/$namespace.wear.MainActivity",'--es','ainotify_event',$id)
        $null = Wait-For { (Get-Ui $WearSerial).OuterXml.Contains($preview) } 'replacement relay watch preview'
        Save-Screenshot $WearSerial 'wear-replacement-relay.png'
        'PASS: First event from an empty replacement relay notified both phone and paired watch'
    } finally {
        Stop-TestRelay $newRelay
        Set-AvdRelay $PhoneSerial 'phone' $port $inboxToken
        $null = Invoke-CheckedAdb $PhoneSerial @('shell','am','force-stop',$package)
        $null = Invoke-CheckedAdb $PhoneSerial @('shell','am','start','-W','-n',"$package/$namespace.mobile.MainActivity",'--ez','ainotify_start','true')
        Start-Sleep -Seconds 4
        $null = Invoke-CheckedAdb $PhoneSerial @('shell','input','keyevent','KEYCODE_HOME')
    }
}

function Test-PushWakeupAndBackgroundSync {
    "Testing push registration, screen-off wakeup, deduplication and background sync..."
    $pushToken = "ci-device-token-" + [Guid]::NewGuid().ToString('N')
    $script:lastPushToken = $pushToken
    $regBody = @{
        token = $pushToken
        device_type = 'android'
        app_id = 'io.github.jerryskywalker.ainotify'
    } | ConvertTo-Json
    $null = Invoke-RestMethod -NoProxy "$url/v1/devices/register" -Method Post -Headers @{Authorization="Bearer $inboxToken"} -ContentType 'application/json' -Body $regBody

    $devs = Invoke-RestMethod -NoProxy "$url/v1/devices" -Headers @{Authorization="Bearer $inboxToken"}
    $expectedMask = "***" + $pushToken.Substring($pushToken.Length - 4)
    $match = $devs.devices | Where-Object { $_.token_mask -eq $expectedMask }
    if (-not $match) { throw "Push device registration did not appear in /v1/devices" }
    if ($match.PSObject.Properties['token'] -and $match.token) { throw "Raw push token exposed in /v1/devices response!" }

    # Stop foreground ReceiveService to verify push wakeup works independently
    $null = & $adb -s $PhoneSerial shell am stopservice "$package/$namespace.mobile.ReceiveService" 2>&1
    Start-Sleep -Seconds 1
    $null = Invoke-CheckedAdb $PhoneSerial @('shell','input','keyevent','KEYCODE_SLEEP')

    $pushId = [Guid]::NewGuid().ToString()
    $pushEvent = @{
        schema_version = 1
        id = $pushId
        tool = 'manual'
        frontend = @{ id = 'push-ci'; label = 'Push CI' }
        kind = 'test'
        device_name = 'Push Trigger'
        occurred_at_ms = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
        message = 'Push Wakeup Delivered Successfully'
        message_truncated = $false
    } | ConvertTo-Json -Depth 4
    $posted = Invoke-RestMethod -NoProxy "$url/v1/events" -Method Post -Headers @{Authorization="Bearer $($writers.win)"} -ContentType 'application/json' -Body $pushEvent

    $deliveries = Invoke-RestMethod -NoProxy "$url/v1/push/deliveries" -Headers @{Authorization="Bearer $inboxToken"}
    $del = $deliveries.deliveries | Where-Object { $_.event_id -eq $pushId }
    if (-not $del) { throw "Relay did not record push delivery for $pushId" }
    if ($del.PSObject.Properties['token'] -and $del.token) { throw "Raw push token exposed in /v1/push/deliveries response!" }
    if ($del.channel -ne 'local_simulation') { throw "Expected channel 'local_simulation' for simulated push delivery" }

    # Leave the event in SQLite and make the first scheduled pull fail with the receiver off.
    Stop-TestRelay $script:relayProcess
    $null = Invoke-CheckedAdb $PhoneSerial @('shell','am','broadcast','-p',$package,'-a','io.github.jerryskywalker.ainotify.PUSH_WAKEUP','--es','event_id',$pushId,'--el','seq',"$($posted.seq)")
    try {
        $null = Wait-For {
            $workerLog = Invoke-CheckedAdb $PhoneSerial @('logcat','-d','-s','AINotifyWork:I')
            ($workerLog -join "`n").Contains("SyncWorker eventId=$pushId result=Retry")
        } 'push worker schedules retry while Relay is down' 45
        if (Test-Notification $PhoneSerial $pushId) { throw 'Phone notified before the Relay recovered.' }
    } finally {
        $script:relayProcess = Start-TestRelay $url $childEnvironment 'relay-after-push-outage'
    }
    $null = Wait-For { Test-Notification $PhoneSerial $pushId } 'push notification after Relay recovers without a second broadcast' 105

    $null = Invoke-CheckedAdb $PhoneSerial @('shell','am','broadcast','-p',$package,'-a','io.github.jerryskywalker.ainotify.PUSH_WAKEUP','--es','event_id',$pushId,'--el','seq',"$($posted.seq)")
    $null = Wait-For {
        $workerLog = Invoke-CheckedAdb $PhoneSerial @('logcat','-d','-s','AINotifyWork:I')
        ($workerLog -join "`n").Contains("SyncWorker eventId=$pushId result=Success fresh=0")
    } 'duplicate push worker finishes with no fresh notifications' 45

    if ($WearMode -eq 'paired') {
        $null = Wait-For { & $adb -s $WearSerial shell input keyevent KEYCODE_WAKEUP 2>$null | Out-Null; Test-Notification $WearSerial $pushId } 'paired watch push notification' 60
        $null = Invoke-CheckedAdb $WearSerial @('shell','am','start','-W','-n',"$package/$namespace.wear.MainActivity",'--es','ainotify_event',$pushId)
        $null = Wait-For { (Get-Ui $WearSerial).OuterXml.Contains('Push Wakeup Delivered Successfully') } 'paired watch push preview' 60
    }

    $null = Invoke-CheckedAdb $PhoneSerial @('shell','input','keyevent','KEYCODE_WAKEUP')
    $null = Invoke-CheckedAdb $PhoneSerial @('shell','wm','dismiss-keyguard')

    $unregBody = @{ token = $pushToken } | ConvertTo-Json
    $null = Invoke-RestMethod -NoProxy "$url/v1/devices/unregister" -Method Post -Headers @{Authorization="Bearer $inboxToken"} -ContentType 'application/json' -Body $unregBody

    $null = & $adb -s $PhoneSerial shell am start-foreground-service "$package/$namespace.mobile.ReceiveService" 2>&1

    $allLogs = (Get-ChildItem -LiteralPath $OutputDir -Filter '*.log' -File | ForEach-Object { Get-Content $_.FullName -Raw }) -join "`n"
    if ($allLogs.Contains($pushToken)) { throw "Raw push token leaked into log files!" }

    'PASS: Relay push registration, screen-off wake, retry after Relay outage and notification deduplication'
}

function Tap-Node([string]$Serial, $Node) {
    if ($Node.bounds -notmatch '^\[(\d+),(\d+)\]\[(\d+),(\d+)\]$') { throw 'UI element has no bounds' }
    $x = ([int]$Matches[1] + [int]$Matches[3]) -shr 1
    $y = ([int]$Matches[2] + [int]$Matches[4]) -shr 1
    $null = Invoke-CheckedAdb $Serial @('shell','input','tap',"$x","$y")
}

function Tap-Item([string]$Serial, [string]$Expected) {
    $node = Wait-For {
        (Get-Ui $Serial).SelectNodes('//node') |
            Where-Object { $_.text -like "*$Expected*" -and $_.package -eq 'com.android.systemui' } |
            Select-Object -First 1
    } "notification visible: $Expected"
    # Android can group replies with the receiver notification. A group summary
    # opens the inbox, so expand its group before clicking the reply itself.
    $parent = $node.ParentNode
    while ($parent -and $parent.Name -eq 'node') {
        $button = $parent.SelectSingleNode('.//node[contains(@resource-id,"expand_button") and contains(@content-desc,"Expand")]')
        if ($button -and $node.'resource-id' -ne 'android:id/title') {
            Tap-Node $Serial $button
            $node = Wait-For {
                (Get-Ui $Serial).SelectNodes('//node') |
                    Where-Object { $_.text -like "*$Expected*" -and $_.'resource-id' -eq 'android:id/title' } |
                    Select-Object -First 1
            } "expanded notification: $Expected"
            break
        }
        $parent = $parent.ParentNode
    }
    Tap-Node $Serial $node
}

[IO.Directory]::CreateDirectory($OutputDir) | Out-Null
$scratch = Join-Path ([IO.Path]::GetTempPath()) ('ainotify-ci-' + [Guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($scratch) | Out-Null
$port = Get-TestRelayPort
$url = "http://127.0.0.1:$port"
$reader = [Guid]::NewGuid().ToString('N')
$inboxToken = [Guid]::NewGuid().ToString('N')
$writers = @{
    win = [Guid]::NewGuid().ToString('N')
    linux = [Guid]::NewGuid().ToString('N')
    desktop = [Guid]::NewGuid().ToString('N')
}
$readHeaders = @{Authorization = "Bearer $reader"}
$childEnvironment = @{
    AINOTIFY_LISTEN = "127.0.0.1:$port"
    AINOTIFY_DB = (Join-Path $scratch 'test.sqlite3')
    AINOTIFY_READER_TOKEN = $reader
    AINOTIFY_INBOX_TOKEN = $inboxToken
    AINOTIFY_WRITERS = ($writers | ConvertTo-Json -Compress)
}
$relayProcess = $null

try {
    foreach ($serial in @($PhoneSerial,$WearSerial)) {
        $avd = (Invoke-CheckedAdb $serial @('emu','avd','name') | Select-Object -First 1).Trim()
        $isWear = [bool](Invoke-CheckedAdb $serial @('shell','pm','list','features') | Where-Object { $_.Trim() -eq 'feature:android.hardware.type.watch' })
        if ($isWear -ne ($serial -eq $WearSerial)) { throw "Wrong emulator type for $serial ($avd)" }
        "$serial $avd"
    }

    $relayProcess = Start-TestRelay
    $rejectedRead = Invoke-WebRequest -NoProxy "$url/v1/events" -Headers @{Authorization="Bearer $($writers.win)"} -SkipHttpErrorCheck
    if ($rejectedRead.StatusCode -ne 401) { throw 'Writer was allowed to read messages' }
    $writeCheck = @{
        Method = 'Post'
        Headers = $readHeaders
        ContentType = 'application/json'
        Body = '{"schema_version":1,"id":"00000000-0000-0000-0000-000000000001","tool":"manual","kind":"test","device_name":"Read only","occurred_at_ms":1}'
        SkipHttpErrorCheck = $true
    }
    $rejectedWrite = Invoke-WebRequest -NoProxy "$url/v1/events" @writeCheck
    if ($rejectedWrite.StatusCode -ne 401) { throw "Reader write request returned $($rejectedWrite.StatusCode)" }

    if ($WearMode -eq 'paired') {
        & $adb -s $PhoneSerial forward tcp:5601 tcp:5601
        & $adb -s $PhoneSerial shell cmd deviceidle whitelist +com.google.android.apps.wear.companion 2>$null | Out-Null
        & $adb -s $PhoneSerial shell cmd deviceidle whitelist +$package 2>$null | Out-Null
        & $adb -s $WearSerial shell cmd deviceidle whitelist +$package 2>$null | Out-Null
        & $adb -s $PhoneSerial shell am start -n com.google.android.apps.wear.companion/.core.application.RootActivity 2>$null | Out-Null
        Start-Sleep -Seconds 1
    }
    Prepare-Avd $WearSerial $wearApk 'wear' ($WearMode -eq 'direct')
    Prepare-Avd $PhoneSerial $phoneApk 'mobile' $true
    Start-Sleep -Seconds 6
    $null = Invoke-CheckedAdb $PhoneSerial @('shell','input','keyevent','KEYCODE_HOME')
    if ($WearMode -eq 'direct') {
        $null = Invoke-CheckedAdb $WearSerial @('shell','input','keyevent','KEYCODE_WAKEUP')
    }

    $body = "原型验收：最后一条回复。" + (("启动测试并保留末尾标记。") * 60) + ' END-AINOTIFY-WINDOWS'
    $cases = @(
        @{id='win';tool='codex';frontend='codex-desktop';frontendLabel='Codex Desktop';name='CI-Windows';project='demo-win';body=$body},
        @{id='linux';tool='claude-code';frontend='claude-code-cli';frontendLabel='Claude Code CLI';name='CI-Linux';project='demo-linux';body='Claude Code 本轮完成。 END-AINOTIFY-LINUX'}
    )

    Stop-TestRelay $relayProcess
    $relayProcess = $null
    foreach ($case in $cases) {
        $state = Join-Path $scratch $case.id
        $toolHome = Join-Path $scratch ("tool-" + $case.id)
        $case.state = $state
        $null = Invoke-ProcessInput $agentExe @('--home',$state,'configure','--name',$case.name,'--relay',$url,'--include-message') $writers[$case.id]
        $null = Invoke-ProcessInput $agentExe @('--home',$state,'hooks','install',$case.tool,'--tool-home',$toolHome,'--frontend-id',$case.frontend,'--frontend-label',$case.frontendLabel) ''
        $file = if ($case.tool -eq 'codex') { 'hooks.json' } else { 'settings.json' }
        $toolSettings = Get-Content -Raw -LiteralPath (Join-Path $toolHome $file) | ConvertFrom-Json
        $parts = $toolSettings.hooks.Stop[0].hooks[0].command.Split(' ')
        if ($parts[0] -ne 'powershell.exe' -or $parts.Count -ne 5) { throw 'Unexpected installed Windows Hook command' }
        $payload = @{
            hook_event_name = 'Stop'
            cwd = ('C:\example\' + $case.project)
            session_id = ('ci-session-' + $case.id)
            turn_id = ('ci-turn-' + $case.id)
            last_assistant_message = $case.body
            prompt = 'This string must not be transported'
        } | ConvertTo-Json -Compress
        $null = Invoke-ProcessInput $parts[0] $parts[1..4] $payload
        $pending = @(Get-ChildItem -LiteralPath (Join-Path $state 'queue') -Filter '*.json')
        if ($pending.Count -ne 1) { throw 'Installed Stop hook failed to write exactly one event' }
        $case.queueFile = $pending[0].FullName
        $case.raw = [IO.File]::ReadAllText($case.queueFile)
        $case.eventId = ($case.raw | ConvertFrom-Json).event.id
        $offline = Invoke-ProcessInput $agentExe @('--home',$state,'run','--once') '' -AllowFailure
        if ($offline.ExitCode -eq 0 -or -not (Test-Path -LiteralPath $case.queueFile)) { throw 'Offline event did not remain queued.' }
    }
    'PASS: Installed native Stop commands accept UTF-8 stdin and preserve offline events'

    $relayProcess = Start-TestRelay
    foreach ($case in $cases) {
        $null = Invoke-ProcessInput $agentExe @('--home',$case.state,'run','--once') ''
        if (Test-Path -LiteralPath $case.queueFile) { throw 'Sent event was not removed from local queue' }
        [IO.File]::WriteAllText($case.queueFile,$case.raw)
        $null = Invoke-ProcessInput $agentExe @('--home',$case.state,'run','--once') ''
        $entry = Invoke-RestMethod -NoProxy "$url/v1/events/$($case.eventId)" -Headers $readHeaders
        if ($entry.message -cne $case.body -or $entry.device_id -ne $case.id -or $entry.project -ne $case.project -or $entry.frontend.id -ne $case.frontend -or $entry.frontend.label -ne $case.frontendLabel) {
            throw 'Persisted reply or source differs from the captured event'
        }
    }
    $first = Invoke-RestMethod -NoProxy "$url/v1/events?after=0&limit=1" -Headers $readHeaders
    $second = Invoke-RestMethod -NoProxy "$url/v1/events?after=$($first.next_cursor)&limit=1" -Headers $readHeaders
    $end = Invoke-RestMethod -NoProxy "$url/v1/events?after=$($second.next_cursor)&limit=1" -Headers $readHeaders
    if ($first.events.Count -ne 1 -or $second.events.Count -ne 1 -or $end.events.Count -ne 0) { throw 'Cursor or deduplication check failed' }

    Stop-TestRelay $relayProcess
    $relayProcess = Start-TestRelay
    $stored = Invoke-RestMethod -NoProxy "$url/v1/events?after=0" -Headers $readHeaders
    if ($stored.events.Count -ne 2) { throw 'Relay did not restore exactly two persisted events' }
    'PASS: Writer/reader roles, restart recovery, stable event IDs, cursor and complete body'

    $phoneId = $cases[0].eventId
    $wearId = $cases[1].eventId
    $null = Invoke-CheckedAdb $PhoneSerial @('shell','input','keyevent','KEYCODE_WAKEUP')
    $null = Invoke-CheckedAdb $PhoneSerial @('shell','wm','dismiss-keyguard')
    $null = Invoke-CheckedAdb $WearSerial @('shell','input','keyevent','KEYCODE_WAKEUP')
    $null = Invoke-CheckedAdb $WearSerial @('shell','wm','dismiss-keyguard')
    $null = Wait-For { Test-Notification $PhoneSerial $phoneId } 'phone alert'
    $null = Wait-For { & $adb -s $WearSerial shell input keyevent KEYCODE_WAKEUP 2>$null | Out-Null; Test-Notification $WearSerial $wearId } "watch alert ($WearMode mode)" 120
    $null = Invoke-CheckedAdb $PhoneSerial @('shell','cmd','statusbar','expand-notifications')
    Start-Sleep -Milliseconds 600
    Tap-Item $PhoneSerial 'CI-Windows'
    $null = Wait-For {
        (Get-Ui $PhoneSerial).OuterXml.Contains('END-AINOTIFY-WINDOWS')
    } 'notification tap opens full reply' 45
    Save-Screenshot $PhoneSerial 'phone-reply.png'

    $null = Invoke-CheckedAdb $WearSerial @('shell','input','keyevent','KEYCODE_WAKEUP')
    $null = Invoke-CheckedAdb $WearSerial @('shell','am','start','-W','-n',"$package/$namespace.wear.MainActivity",
        '--es','ainotify_event',$wearId)
    $null = Wait-For {
        $ui = Get-Ui $WearSerial
        $ui.OuterXml.Contains('END-AINOTIFY-LINUX')
    } 'watch reply preview'
    Save-Screenshot $WearSerial 'wear-preview.png'
    "PASS: Android notification tap and full reply; Wear OS notification and preview ($WearMode mode)"

    try {
        Run-PhoneInboxChecks
    } catch {
        $failure = $_
        try {
            (Get-Ui $PhoneSerial).OuterXml | Set-Content -LiteralPath (Join-Path $OutputDir 'phone-inbox-failure.xml') -Encoding utf8NoBOM
            Save-Screenshot $PhoneSerial 'phone-inbox-failure.png'
        } catch {
            Write-Warning 'Could not capture the phone UI after failure.'
        }
        throw $failure
    }

    if (-not $SkipDesktop) {
        $smoke = @{
            DesktopExe = $desktopExe
            StateDir = (Join-Path $scratch 'desktop')
            RelayUrl = $url
            WriterToken = $writers.desktop
        }
        & (Join-Path $AgentRoot 'scripts/desktop-smoke.ps1') @smoke
    }

    $pairedChecks = @()
    if ($WearMode -eq 'paired') {
        Test-PairedRelaySwitch
        $pairedChecks += 'paired-relay-switch-first-event'
    }

    Test-PushWakeupAndBackgroundSync
    $pushChecks = @('relay-device-register','push-wakeup-screen-off','push-worker-retry-after-relay-outage','push-dedup','push-device-unregister')
    if ($WearMode -eq 'paired') {
        $pushChecks += 'paired-push-wear-sync'
    }

    $revisions = @{}
    foreach ($repo in @($AgentRoot,$RelayRoot,$AndroidRoot,(Split-Path -Parent $PSScriptRoot))) {
        $name = Split-Path $repo -Leaf
        $commit = & git -C $repo rev-parse --verify --quiet HEAD
        $dirty = [bool](& git -C $repo status --porcelain)
        $revisions[$name] = @{ commit = $commit; dirty = $dirty }
    }
    @{
        phone = $PhoneSerial
        wear = $WearSerial
        wear_mode = $WearMode
        passed = @('hook-stdin','offline-retry','auth','sqlite-restart','dedup','cursor','phone-notification','phone-detail','wear-notification','wear-preview','frontend-identity','device-group-filters','phone-swipes','phone-undo','relay-inbox-auth','relay-inbox-idempotency','phone-offline-recovery','phone-trash-restore','phone-language-theme-accent') + $pairedChecks + $pushChecks
        desktop = if ($SkipDesktop) { 'skipped' } else { 'passed' }
        real_ai_sessions = 'not run by this offline integration check'
        revisions = $revisions
    } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $OutputDir 'receipt.json') -Encoding utf8NoBOM

    if ($script:lastPushToken) {
        $receiptText = Get-Content -Raw -LiteralPath (Join-Path $OutputDir 'receipt.json')
        if ($receiptText.Contains($script:lastPushToken)) { throw "Raw push token leaked into receipt.json!" }
    }
} finally {
    Stop-TestRelay $relayProcess
    foreach ($serial in @($PhoneSerial,$WearSerial)) {
        & $adb -s $serial shell am force-stop $package 2>$null | Out-Null
    }
}
