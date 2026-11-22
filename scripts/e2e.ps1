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
    [switch]$SkipDesktop
)

$ErrorActionPreference = 'Stop'
$package = 'io.github.jerryskywalker.ainotify.dev'
$namespace = 'io.github.jerryskywalker.ainotify'
. (Join-Path $PSScriptRoot 'phone-inbox-ci.ps1')
$adb = Join-Path $SdkRoot 'platform-tools/adb.exe'
$profile = if ($DebugRust) { 'debug' } else { 'release' }
$agentExe = Join-Path $AgentRoot "target/$profile/ai-notify-agent.exe"
$desktopExe = Join-Path $AgentRoot "target/$profile/ai-notify-desktop.exe"
$relayExe = Join-Path $RelayRoot "target/$profile/ai-notify-relay.exe"
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

function Start-TestRelay {
    $arguments = @{
        FilePath = $relayExe
        Environment = $childEnvironment
        PassThru = $true
        WindowStyle = 'Hidden'
        RedirectStandardOutput = (Join-Path $OutputDir 'relay.stdout.log')
        RedirectStandardError = (Join-Path $OutputDir 'relay.stderr.log')
    }
    $process = Start-Process @arguments
    try {
        $null = Wait-For {
            if ($process.HasExited) { throw 'Relay exited during startup.' }
            try { (Invoke-RestMethod -NoProxy "$url/healthz" -TimeoutSec 2).ok } catch { }
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

function Prepare-Avd([string]$Serial, [string]$Apk, [string]$Flavor, [bool]$Direct) {
    $null = Invoke-CheckedAdb $Serial @('install','-r',$Apk)
    # CI owns the .dev application data on explicitly selected emulators.
    $null = Invoke-CheckedAdb $Serial @('shell','pm','clear',$package)
    $null = Invoke-CheckedAdb $Serial @('shell','pm','grant',$package,'android.permission.POST_NOTIFICATIONS')
    if ($Flavor -eq 'mobile') {
        $null = Invoke-CheckedAdb $Serial @('shell','cmd','locale','set-app-locales',$package,'--locales','en')
    }
    if ($Direct) {
        $credential = if ($Flavor -eq 'mobile') { $inboxToken } else { $reader }
        $settings = @{relay="http://10.0.2.2:$port";token=$credential} | ConvertTo-Json -Compress
        $settingsName = if ($Flavor -eq 'mobile') { 'phone' } else { 'wear' }
        $null = Invoke-ProcessInput $adb @('-s',$Serial,'shell','-T',"run-as $package sh -c 'mkdir -p files && cat > files/$settingsName-settings.json'") $settings
    }
    $null = Invoke-CheckedAdb $Serial @('shell','am','start','-W','-n',"$package/$namespace.$Flavor.MainActivity",'--ez','ainotify_start','true')
}

function Test-Notification([string]$Serial, [string]$Id) {
    $records = Invoke-CheckedAdb $Serial @('shell','cmd','notification','list')
    [bool]($records | Where-Object { $_.Contains("|$package|") -and $_.Contains("|$Id|") } | Select-Object -First 1)
}

function Get-Ui([string]$Serial) {
    $null = Invoke-CheckedAdb $Serial @('shell','uiautomator','dump','/sdcard/ainotify-ci.xml')
    $raw = Invoke-CheckedAdb $Serial @('exec-out','cat','/sdcard/ainotify-ci.xml')
    [xml]($raw -join [Environment]::NewLine)
}

function Save-Screenshot([string]$Serial, [string]$Name) {
    $file = Join-Path $OutputDir $Name
    & $adb -s $Serial exec-out screencap -p > $file
    if ($LASTEXITCODE -or (Get-Item -LiteralPath $file).Length -lt 128) { throw "Screenshot failed on $Serial" }
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
$listener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, 0)
$listener.Start()
$port = $listener.LocalEndpoint.Port
$listener.Stop()
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

    Prepare-Avd $PhoneSerial $phoneApk 'mobile' $true
    Prepare-Avd $WearSerial $wearApk 'wear' ($WearMode -eq 'direct')
    $null = Invoke-CheckedAdb $PhoneSerial @('shell','input','keyevent','KEYCODE_HOME')
    $null = Invoke-CheckedAdb $WearSerial @('shell','input','keyevent','KEYCODE_HOME')

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
    $null = Wait-For { Test-Notification $PhoneSerial $phoneId } 'phone alert'
    $null = Wait-For { Test-Notification $WearSerial $wearId } "watch alert ($WearMode mode)"
    $null = Invoke-CheckedAdb $PhoneSerial @('shell','cmd','statusbar','expand-notifications')
    Tap-Item $PhoneSerial 'CI-Windows'
    $null = Wait-For {
        $ui = Get-Ui $PhoneSerial
        if (-not $ui.OuterXml.Contains('END-AINOTIFY-WINDOWS')) {
            $ui.SelectNodes('//node') | Where-Object { $_.package -eq $package } |
                ForEach-Object { $_.text } | Set-Content -LiteralPath (Join-Path $OutputDir 'phone-ui.txt')
            Save-Screenshot $PhoneSerial 'phone-current.png'
        }
        $ui.OuterXml.Contains('END-AINOTIFY-WINDOWS')
    } 'notification tap opens full reply'
    Save-Screenshot $PhoneSerial 'phone-reply.png'

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
        passed = @('hook-stdin','offline-retry','auth','sqlite-restart','dedup','cursor','phone-notification','phone-detail','wear-notification','wear-preview','frontend-identity','device-group-filters','phone-swipes','phone-undo','relay-inbox-auth','relay-inbox-idempotency','phone-offline-recovery','phone-trash-restore','phone-language-theme-accent')
        desktop = if ($SkipDesktop) { 'skipped' } else { 'passed' }
        real_ai_sessions = 'not run by this offline integration check'
        revisions = $revisions
    } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $OutputDir 'receipt.json') -Encoding utf8NoBOM
} finally {
    Stop-TestRelay $relayProcess
    foreach ($serial in @($PhoneSerial,$WearSerial)) {
        & $adb -s $serial shell am force-stop $package 2>$null | Out-Null
    }
}
