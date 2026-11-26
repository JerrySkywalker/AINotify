# Dot-sourced by e2e.ps1. Uses its isolated relay, credentials, and phone AVD.
function Get-PhoneNode([string]$Expected, [switch]$Contains, [int]$Seconds = 18) {
    Wait-For {
        (Get-Ui $PhoneSerial).SelectNodes('//node') | Where-Object {
            $_.package -eq $package -and (
                $_.text -ceq $Expected -or $_.'content-desc' -ceq $Expected -or
                ($Contains -and ($_.text.Contains($Expected) -or $_.'content-desc'.Contains($Expected)))
            )
        } | Select-Object -First 1
    } "phone UI: $Expected" $Seconds
}

function Tap-Phone([string]$Label, [switch]$Contains) {
    Tap-Node $PhoneSerial (Get-PhoneNode $Label -Contains:$Contains)
}

function Select-PhoneTab([string]$Name) {
    Wait-For {
        $node = (Get-Ui $PhoneSerial).SelectNodes('//node') | Where-Object {
            $_.package -eq $package -and $_.text -eq $Name
        } | Select-Object -First 1
        if ($node) {
            $tab = $node.ParentNode
            if ($tab -and $tab.selected -eq 'true') { return $true }
            Tap-Node $PhoneSerial $(if ($tab) { $tab } else { $node })
            Start-Sleep -Milliseconds 600
            $check = (Get-Ui $PhoneSerial).SelectNodes('//node') | Where-Object {
                $_.package -eq $package -and $_.text -eq $Name
            } | Select-Object -First 1
            if ($check -and $check.ParentNode -and $check.ParentNode.selected -eq 'true') { return $true }
        }
        $null
    } "phone tab: $Name" 20
}

function Assert-PhoneMissing([string]$Label) {
    if ((Get-Ui $PhoneSerial).OuterXml.Contains($Label)) { throw "Unexpected phone result: $Label" }
}

function Gesture-Phone([string]$Label, [ValidateSet('left','right')][string]$Direction, [switch]$Short) {
    $node = Get-PhoneNode $Label -Contains
    # Use the message center and stay away from the Android back-gesture edges.
    if ($node.bounds -notmatch '^\[(\d+),(\d+)\]\[(\d+),(\d+)\]$') { throw 'Reply row has no bounds.' }
    $y = ([int]$Matches[2] + [int]$Matches[4]) -shr 1
    $size = (Invoke-CheckedAdb $PhoneSerial @('shell','wm','size') | Select-Object -Last 1)
    if ($size -notmatch '(\d+)x(\d+)') { throw 'Could not resolve the phone screen size.' }
    $a = [int]([int]$Matches[1] * 0.16)
    $b = [int]([int]$Matches[1] * $(if ($Short) { 0.29 } else { 0.82 }))
    if ($Direction -eq 'left') { $from = $b; $to = $a } else { $from = $a; $to = $b }
    $duration = if ($Short) { '650' } else { '400' }
    $null = Invoke-CheckedAdb $PhoneSerial @('shell','input','swipe',"$from","$y","$to","$y",$duration)
}

function Test-PhoneBackground([string]$Name, [string]$Hex) {
    Save-Screenshot $PhoneSerial $Name
    $image = [Drawing.Bitmap]::new((Join-Path $OutputDir $Name))
    try {
        # The screen's outer gutter is the theme surface, outside the text and cards.
        $rgb = $image.GetPixel(3, [int]($image.Height / 2))
        ('{0:X2}{1:X2}{2:X2}' -f $rgb.R,$rgb.G,$rgb.B) -eq $Hex
    } finally {
        $image.Dispose()
    }
}

function Get-RelayMailState([string]$Id) {
    (Invoke-RestMethod -NoProxy "$url/v1/inbox/changes?after=0" -Headers $readHeaders).changes |
        Where-Object event_id -eq $Id | Select-Object -First 1
}

function Write-RelayMailAction([hashtable]$Action, [hashtable]$Headers) {
    Invoke-WebRequest -NoProxy "$url/v1/inbox/actions" -Headers $Headers -Method Post -ContentType 'application/json' -Body ($Action | ConvertTo-Json -Compress) -SkipHttpErrorCheck
}

function Run-PhoneInboxChecks {
    Add-Type -AssemblyName System.Drawing.Common
    $phonePackage = "$package/$namespace.mobile.MainActivity"
    $codex = 'CI-Windows · Codex Desktop · demo-win'
    $claude = 'CI-Linux · Claude Code CLI · demo-linux'
    $thirdId = [Guid]::NewGuid().ToString()
    $third = 'CI-Windows · Codex CLI · CLI-only'
    $inboxHeaders = @{ Authorization = "Bearer $inboxToken" }
    $extraEvent = @{
        schema_version = 1; id = $thirdId; tool = 'codex'; kind = 'turn.completed'; device_name = 'CI-Windows'
        occurred_at_ms = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds(); project = 'CLI-only'; message = 'CI alternate frontend'
        frontend = @{ id = 'codex-cli'; label = 'Codex CLI' }
    } | ConvertTo-Json -Compress
    $null = Invoke-RestMethod -NoProxy "$url/v1/events" -Method Post -ContentType 'application/json' -Body $extraEvent -Headers @{Authorization = "Bearer $($writers.win)"}
    Tap-Phone 'Back'
    $null = Get-PhoneNode $third -Contains
    Save-Screenshot $PhoneSerial 'phone-inbox-light.png'

    $pin = @{ id = [Guid]::NewGuid().ToString(); event_id = $thirdId; pinned = $true }
    $writer = @{ Authorization = "Bearer $($writers.win)" }
    if ((Write-RelayMailAction $pin $readHeaders).StatusCode -ne 403 -or (Write-RelayMailAction $pin $writer).StatusCode -ne 401) {
        throw 'Inbox mutation permission failure.'
    }
    $reject = Invoke-WebRequest -NoProxy "$url/v1/events" -Headers $inboxHeaders -Method Post -ContentType 'application/json' -Body $extraEvent -SkipHttpErrorCheck
    if ($reject.StatusCode -ne 401) { throw 'Inbox token was allowed to ingest events.' }
    $first = Write-RelayMailAction $pin $inboxHeaders
    $repeat = Write-RelayMailAction $pin $inboxHeaders
    if ($first.StatusCode -ne 200 -or $repeat.StatusCode -ne 200 -or $repeat.Content -ne $first.Content) {
        throw 'Inbox action retry is not idempotent.'
    }
    $pin.pinned = $false
    if ((Write-RelayMailAction $pin $inboxHeaders).StatusCode -ne 409) { throw 'Reused action ID did not reject a changed payload.' }
    $null = Get-PhoneNode 'Pinned' -Contains
    $remote = @{ id = [Guid]::NewGuid().ToString(); event_id = $thirdId; folder = 'archive' }
    $result = Write-RelayMailAction $remote $inboxHeaders
    $state = $result.Content | ConvertFrom-Json
    if ($result.StatusCode -ne 200 -or -not $state.pinned -or $state.folder -ne 'archive') { throw 'Remote folder patch lost pin state.' }

    Tap-Phone 'Settings'
    Tap-Phone 'Theme'
    Tap-Phone 'Dark graphite'
    Tap-Phone 'Create group'
    Tap-Phone 'Group name' -Contains
    Start-Sleep -Milliseconds 800
    $groupName = ''
    foreach ($character in 'F','a','r','m') {
        $null = Invoke-CheckedAdb $PhoneSerial @('shell','input','text',$character)
        $groupName += $character
        $null = Get-PhoneNode $groupName -Seconds 15
    }
    $null = Invoke-CheckedAdb $PhoneSerial @('shell','input','keyevent','KEYCODE_BACK')
    Start-Sleep -Milliseconds 500
    Tap-Phone 'CI-Linux' -Contains
    Tap-Phone 'Save'
    $null = Get-PhoneNode 'Farm' -Contains
    Tap-Phone 'Back'

    Tap-Phone 'Devices and groups' -Contains
    $null = Get-PhoneNode 'Done'
    Tap-Phone 'Members'
    $null = Get-PhoneNode 'Hide members'
    Tap-Phone 'Farm' -Contains
    Tap-Phone 'Done'
    Start-Sleep -Milliseconds 600
    $null = Get-PhoneNode $claude -Contains
    Assert-PhoneMissing $codex
    Tap-Phone 'Devices and groups' -Contains
    $null = Get-PhoneNode 'Done'
    Tap-Phone 'CI-Windows' -Contains
    Save-Screenshot $PhoneSerial 'phone-filters-graphite.png'
    Tap-Phone 'Done'
    Start-Sleep -Milliseconds 600
    Tap-Phone 'AI frontends' -Contains
    $null = Get-PhoneNode 'Done'
    Tap-Phone 'Codex Desktop' -Contains
    Tap-Phone 'Done'
    Start-Sleep -Milliseconds 600
    $null = Get-PhoneNode $codex -Contains
    Assert-PhoneMissing $claude
    Tap-Phone 'AI frontends' -Contains
    $null = Get-PhoneNode 'Done'
    Tap-Phone 'Claude Code CLI' -Contains
    Tap-Phone 'Done'
    Start-Sleep -Milliseconds 600
    $null = Get-PhoneNode $claude -Contains
    $null = Get-PhoneNode $codex -Contains
    Assert-PhoneMissing $third
    Select-PhoneTab 'Archive'
    $null = Get-PhoneNode 'No replies match these filters.'
    Select-PhoneTab 'Inbox'
    Start-Sleep -Milliseconds 400
    Tap-Phone 'Clear filters'
    Start-Sleep -Milliseconds 400
    'PASS: Device groups, selections and independent frontend facets in the phone UI'

    Gesture-Phone $codex 'right' -Short
    Assert-PhoneMissing 'Pinned'
    Start-Sleep -Seconds 3
    Gesture-Phone $codex 'right'
    $pinState = Wait-For {
        $candidate = Get-RelayMailState $phoneId
        if ($candidate.pinned) { return $candidate }
        Start-Sleep -Milliseconds 2500
        $candidate = Get-RelayMailState $phoneId
        if ($candidate.pinned) { return $candidate }
        Gesture-Phone $codex 'right'
        $null
    } 'phone right swipe pins at relay' 30
    $null = Get-PhoneNode $codex -Contains
    if ($pinState.seq -ne $state.seq + 1) { throw 'A single swipe must submit one operation.' }
    Start-Sleep -Seconds 3
    Gesture-Phone $codex 'left'
    $null = Wait-For {
        $candidate = Get-RelayMailState $phoneId
        if ($candidate.folder -eq 'archive') { return $candidate }
        Start-Sleep -Milliseconds 2500
        $candidate = Get-RelayMailState $phoneId
        if ($candidate.folder -eq 'archive') { return $candidate }
        Gesture-Phone $codex 'left'
        $null
    } 'phone left swipe archives at relay before undo' 30
    Start-Sleep -Milliseconds 300
    Tap-Phone 'Undo'
    $null = Wait-For {
        $state = Get-RelayMailState $phoneId
        $state.folder -eq 'inbox' -and $state.pinned -and $state.seq -eq $pinState.seq + 2
    } 'undo returns the reply to inbox' 30
    $null = Get-PhoneNode $codex -Contains
    Start-Sleep -Seconds 3
    Gesture-Phone $codex 'left'
    $null = Wait-For {
        $state = Get-RelayMailState $phoneId
        if ($state.folder -eq 'archive' -and $state.pinned) { return $state }
        Start-Sleep -Milliseconds 2500
        $state = Get-RelayMailState $phoneId
        if ($state.folder -eq 'archive' -and $state.pinned) { return $state }
        Gesture-Phone $codex 'left'
        $null
    } 'phone left swipe archives at relay' 30
    Start-Sleep -Milliseconds 600
    Select-PhoneTab 'Archive'
    $null = Get-PhoneNode $codex -Contains
    $null = Get-PhoneNode $third -Contains

    Tap-Phone 'Settings'
    Tap-Phone 'Swipe right'
    Tap-Phone 'None'
    Tap-Phone 'Back'
    Gesture-Phone $codex 'right'
    $null = Get-PhoneNode $codex -Contains
    if ((Get-RelayMailState $phoneId).folder -ne 'archive') { throw 'Disabled swipe changed the reply.' }
    Tap-Phone 'Settings'
    Tap-Phone 'Swipe right'
    Tap-Phone 'Move to trash'
    Save-Screenshot $PhoneSerial 'phone-settings-graphite.png'
    Tap-Phone 'Back'
    Stop-TestRelay $script:relayProcess
    $script:relayProcess = $null
    Gesture-Phone $codex 'right'
    Start-Sleep -Milliseconds 600
    Select-PhoneTab 'Trash'
    $null = Get-PhoneNode $codex -Contains
    $null = Get-PhoneNode 'Pending sync' -Contains
    $null = Invoke-CheckedAdb $PhoneSerial @('shell','am','force-stop',$package)
    $null = Invoke-CheckedAdb $PhoneSerial @('shell','am','start','-W','-n',$phonePackage,'--ez','ainotify_start','true')
    Start-Sleep -Seconds 3
    $null = Get-PhoneNode $codex -Contains
    $null = Get-PhoneNode 'Pending sync' -Contains
    $null = Wait-For { Test-PhoneBackground 'phone-pending-graphite.png' '10161A' } 'graphite background'
    $script:relayProcess = Start-TestRelay
    $null = Wait-For { (Get-RelayMailState $phoneId).folder -eq 'trash' } 'persisted offline action sync after restart'
    $null = Wait-For { -not (Get-Ui $PhoneSerial).OuterXml.Contains('Pending sync') } 'pending indicator clears'
    Tap-Phone 'Reply actions'
    Tap-Phone 'Move to inbox'
    $null = Wait-For {
        $state = Get-RelayMailState $phoneId
        $state.folder -eq 'inbox' -and $state.pinned
    } 'restore from trash preserves pin'
    'PASS: Native right and left swipes, undo, relay patching, offline restart and trash restore'

    Tap-Phone 'Settings'
    Tap-Phone 'Theme'
    Tap-Phone 'AMOLED black'
    Tap-Phone 'Accent color'
    Tap-Phone 'Blue'
    Tap-Phone 'Language'
    Tap-Phone '简体中文'
    $null = Get-PhoneNode 'AMOLED 纯黑' -Contains
    $null = Get-PhoneNode '蓝色' -Contains
    $null = Wait-For { Test-PhoneBackground 'phone-settings-amoled-zh.png' '000000' } 'AMOLED true-black background'
    $null = Invoke-CheckedAdb $PhoneSerial @('shell','am','force-stop',$package)
    $null = Invoke-CheckedAdb $PhoneSerial @('shell','am','start','-W','-n',$phonePackage,'--ez','ainotify_start','true')
    Start-Sleep -Seconds 3
    Tap-Phone '设置'
    $null = Get-PhoneNode 'AMOLED 纯黑' -Contains
    $null = Get-PhoneNode '蓝色' -Contains
    Tap-Phone '语言'
    Tap-Phone 'English'
    $null = Get-PhoneNode 'Language'
    Tap-Phone 'Theme'
    Tap-Phone 'Light'
    $null = Get-PhoneNode 'Light' -Contains
    Tap-Phone 'Theme'
    Tap-Phone 'Follow system'
    $null = Get-PhoneNode 'Follow system' -Contains
    $night = (Invoke-CheckedAdb $PhoneSerial @('shell','cmd','uimode','night') | Select-Object -Last 1).Trim()
    if ($night -match '^Night mode: (yes|no|auto)$') {
        $original = $Matches[1]
        try {
            $null = Invoke-CheckedAdb $PhoneSerial @('shell','cmd','uimode','night','yes')
            $null = Wait-For { Test-PhoneBackground 'phone-system-dark.png' '10161A' } 'system dark appearance'
            $null = Invoke-CheckedAdb $PhoneSerial @('shell','cmd','uimode','night','no')
            $null = Wait-For { Test-PhoneBackground 'phone-system-light.png' 'F5FAF7' } 'system light appearance'
        } finally {
            $null = Invoke-CheckedAdb $PhoneSerial @('shell','cmd','uimode','night',$original)
        }
    }
    Tap-Phone 'Language'
    Tap-Phone 'Follow system'
    $null = Wait-For {
        (Invoke-CheckedAdb $PhoneSerial @('shell','cmd','locale','get-app-locales',$package)) -match 'are \[\]'
    } 'system language choice'
    'PASS: App language, theme, accent, palette pixels and system appearance'
}
