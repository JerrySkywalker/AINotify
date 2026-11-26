#requires -Version 7.4
param(
    [string]$RelayExe = "C:\Users\jerry\Documents\ChatGPT\AI-Notify\ai-notify-relay\target-ci\release\ai-notify-relay.exe"
)

$ErrorActionPreference = 'Stop'

function Get-FreePort {
    $listener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, 0)
    $listener.Start()
    try { $listener.LocalEndpoint.Port } finally { $listener.Stop() }
}

function Wait-Health($Url) {
    for ($i = 0; $i -lt 30; $i++) {
        try {
            if ((Invoke-RestMethod -NoProxy "$Url/healthz" -TimeoutSec 1).ok) { return $true }
        } catch { }
        Start-Sleep -Milliseconds 200
    }
    throw "Relay at $Url failed to respond to /healthz"
}

$scratch = Join-Path ([IO.Path]::GetTempPath()) ("ainotify-drill-" + [Guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($scratch) | Out-Null
Write-Host "Drill scratch directory: $scratch"

try {
    $dbPath = Join-Path $scratch "live.sqlite3"
    $backupPath = Join-Path $scratch "backup.sqlite3"
    $restoredKeepPath = Join-Path $scratch "restored-keep.sqlite3"
    $restoredResetPath = Join-Path $scratch "restored-reset.sqlite3"

    $port = Get-FreePort
    $url = "http://127.0.0.1:$port"
    $oldReader = "old-reader-" + [Guid]::NewGuid().ToString('N')
    $oldInbox = "old-inbox-" + [Guid]::NewGuid().ToString('N')
    $oldWriter = "old-writer-" + [Guid]::NewGuid().ToString('N')
    $writerMap = @{ win = $oldWriter } | ConvertTo-Json -Compress

    $env1 = @{
        AINOTIFY_LISTEN = "127.0.0.1:$port"
        AINOTIFY_DB = $dbPath
        AINOTIFY_READER_TOKEN = $oldReader
        AINOTIFY_INBOX_TOKEN = $oldInbox
        AINOTIFY_WRITERS = $writerMap
    }

    Write-Host "[1/6] Starting live Relay daemon..."
    $proc1 = Start-Process -FilePath $RelayExe -Environment $env1 -PassThru -WindowStyle Hidden
    try {
        Wait-Health $url | Out-Null

        # Register push device
        $deviceBody = @{ token = "ci-device-token-secret-1234"; device_type = "android"; app_id = "io.github.jerryskywalker.ainotify" } | ConvertTo-Json
        Invoke-RestMethod -NoProxy "$url/v1/devices/register" -Method Post -Headers @{Authorization="Bearer $oldInbox"} -ContentType 'application/json' -Body $deviceBody | Out-Null

        # Check devices output does not contain raw token
        $devicesRaw = Invoke-RestMethod -NoProxy "$url/v1/devices" -Headers @{Authorization="Bearer $oldReader"}
        $devJson = $devicesRaw | ConvertTo-Json -Compress
        if ($devJson.Contains("ci-device-token-secret-1234")) { throw "Raw token found in /v1/devices response!" }
        if (-not $devJson.Contains("***1234")) { throw "Masked token not found in /v1/devices response!" }
        Write-Host "PASS: /v1/devices hides raw token and provides token_mask"

        # Post 3 events
        $eventIds = @()
        for ($i = 1; $i -le 3; $i++) {
            $eId = [Guid]::NewGuid().ToString()
            $eventIds += $eId
            $event = @{
                schema_version = 1; id = $eId; tool = 'codex'; kind = 'turn.completed'
                device_name = 'PC'; occurred_at_ms = 1000 * $i; message = "Message $i"
            } | ConvertTo-Json
            Invoke-RestMethod -NoProxy "$url/v1/events" -Method Post -Headers @{Authorization="Bearer $oldWriter"} -ContentType 'application/json' -Body $event | Out-Null
        }

        # Check push deliveries response
        $deliveries = Invoke-RestMethod -NoProxy "$url/v1/push/deliveries" -Headers @{Authorization="Bearer $oldReader"}
        $delJson = $deliveries | ConvertTo-Json -Compress
        if ($delJson.Contains("ci-device-token-secret-1234")) { throw "Raw token found in /v1/push/deliveries response!" }
        if (-not $delJson.Contains("***1234")) { throw "Masked token not found in /v1/push/deliveries response!" }
        if (-not $delJson.Contains("local_simulation")) { throw "channel 'local_simulation' not found in deliveries!" }
        Write-Host "PASS: /v1/push/deliveries hides raw token and records local_simulation channel"

        # Perform an inbox action
        $action = @{
            id = [Guid]::NewGuid().ToString()
            event_id = $eventIds[0]
            folder = 'archive'
            pinned = $true
        } | ConvertTo-Json
        Invoke-RestMethod -NoProxy "$url/v1/inbox/actions" -Method Post -Headers @{Authorization="Bearer $oldInbox"} -ContentType 'application/json' -Body $action | Out-Null

        $feed1 = Invoke-RestMethod -NoProxy "$url/v1/events?after=0&limit=50" -Headers @{Authorization="Bearer $oldReader"}
        $originalStreamId = $feed1.stream_id
        if ($feed1.events.Count -ne 3 -or -not $originalStreamId) { throw "Initial feed verification failed" }

        $inboxChanges1 = Invoke-RestMethod -NoProxy "$url/v1/inbox/changes?after=0&limit=50" -Headers @{Authorization="Bearer $oldInbox"}
        if ($inboxChanges1.changes.Count -ne 1 -or $inboxChanges1.next_cursor -ne 1) { throw "Initial inbox changes verification failed" }
    } finally {
        Stop-Process -Id $proc1.Id -Force -ErrorAction SilentlyContinue
        $proc1.WaitForExit(3000) | Out-Null
    }

    Write-Host "[2/6] Performing online backup via CLI..."
    $backupOutput = & $RelayExe backup --db $dbPath --output $backupPath
    if (-not (Test-Path $backupPath)) { throw "Backup file was not created: $backupPath" }
    Write-Host "PASS: CLI backup completed successfully: $backupOutput"

    Write-Host "[3/6] Performing event pruning via CLI..."
    $pruneOutput = & $RelayExe prune --db $dbPath --keep-last 1
    Write-Host "PASS: CLI prune completed: $pruneOutput"

    # Start relay on pruned DB to verify pruning took effect
    $procPruned = Start-Process -FilePath $RelayExe -Environment $env1 -PassThru -WindowStyle Hidden
    try {
        Wait-Health $url | Out-Null
        $feedPruned = Invoke-RestMethod -NoProxy "$url/v1/events?after=0&limit=50" -Headers @{Authorization="Bearer $oldReader"}
        if ($feedPruned.events.Count -ne 1) { throw "Pruning failed: expected 1 event, got $($feedPruned.events.Count)" }
        Write-Host "PASS: Pruned DB contains exactly 1 retained event"
    } finally {
        Stop-Process -Id $procPruned.Id -Force -ErrorAction SilentlyContinue
        $procPruned.WaitForExit(3000) | Out-Null
    }

    Write-Host "[4/6] Performing in-place restore without stream_id reset..."
    $restoreKeepOutput = & $RelayExe restore --input $backupPath --db $restoredKeepPath
    Write-Host "PASS: Restore (keep stream) output: $restoreKeepOutput"

    $envKeep = $env1.Clone()
    $envKeep.AINOTIFY_DB = $restoredKeepPath
    $procKeep = Start-Process -FilePath $RelayExe -Environment $envKeep -PassThru -WindowStyle Hidden
    try {
        Wait-Health $url | Out-Null
        $feedKeep = Invoke-RestMethod -NoProxy "$url/v1/events?after=0&limit=50" -Headers @{Authorization="Bearer $oldReader"}
        if ($feedKeep.stream_id -ne $originalStreamId) { throw "Stream ID changed on in-place restore!" }
        if ($feedKeep.events.Count -ne 3) { throw "Restored DB missing events!" }

        # Client querying with previous stream_id and cursor = 2
        $resumeCheck = Invoke-RestMethod -NoProxy "$url/v1/events?stream_id=$originalStreamId&after=2&limit=50" -Headers @{Authorization="Bearer $oldReader"}
        if ($resumeCheck.reset_cursor) { throw "Expected reset_cursor to be false for matching stream_id" }
        if ($resumeCheck.events.Count -ne 1) { throw "Expected 1 event after cursor 2" }

        # Verify inbox cursor resumes
        $inboxKeep = Invoke-RestMethod -NoProxy "$url/v1/inbox/changes?after=0&limit=50" -Headers @{Authorization="Bearer $oldInbox"}
        if ($inboxKeep.changes.Count -ne 1 -or $inboxKeep.changes[0].folder -ne 'archive') { throw "Restored inbox state mismatch" }
        Write-Host "PASS: In-place restore preserved stream_id, event cursors, and inbox state"
    } finally {
        Stop-Process -Id $procKeep.Id -Force -ErrorAction SilentlyContinue
        $procKeep.WaitForExit(3000) | Out-Null
    }

    Write-Host "[5/6] Performing snapshot rollback with --reset-stream-id..."
    $restoreResetOutput = & $RelayExe restore --input $backupPath --db $restoredResetPath --reset-stream-id
    Write-Host "PASS: Restore (reset stream) output: $restoreResetOutput"

    $envReset = $env1.Clone()
    $envReset.AINOTIFY_DB = $restoredResetPath
    $procReset = Start-Process -FilePath $RelayExe -Environment $envReset -PassThru -WindowStyle Hidden
    try {
        Wait-Health $url | Out-Null
        $feedReset = Invoke-RestMethod -NoProxy "$url/v1/events?after=0&limit=50" -Headers @{Authorization="Bearer $oldReader"}
        if ($feedReset.stream_id -eq $originalStreamId) { throw "Stream ID was NOT reset!" }

        # Client querying with previous stream_id and cursor = 2 triggers reset_cursor
        $rewindCheck = Invoke-RestMethod -NoProxy "$url/v1/events?stream_id=$originalStreamId&after=2&limit=50" -Headers @{Authorization="Bearer $oldReader"}
        if (-not $rewindCheck.reset_cursor) { throw "Expected reset_cursor: true when stream_id changed!" }
        if ($rewindCheck.events.Count -ne 3) { throw "Expected full event replay from sequence 0" }

        # Phone inbox sync cursor check
        $inboxReset = Invoke-RestMethod -NoProxy "$url/v1/inbox/changes?after=0&limit=50" -Headers @{Authorization="Bearer $oldInbox"}
        if ($inboxReset.changes.Count -ne 1 -or $inboxReset.changes[0].folder -ne 'archive') { throw "Inbox state on reset stream mismatch" }
        Write-Host "PASS: Reset-stream rollback triggered reset_cursor: true; clients re-sync smoothly"
    } finally {
        Stop-Process -Id $procReset.Id -Force -ErrorAction SilentlyContinue
        $procReset.WaitForExit(3000) | Out-Null
    }

    Write-Host "[6/6] Verifying zero-downtime credential rotation and revocation..."
    $newReader = "new-reader-" + [Guid]::NewGuid().ToString('N')
    $newInbox = "new-inbox-" + [Guid]::NewGuid().ToString('N')
    $newWriter = "new-writer-" + [Guid]::NewGuid().ToString('N')
    $writerMapRotated = @{ win = "$oldWriter,$newWriter" } | ConvertTo-Json -Compress

    # Phase 1: Dual credentials (requires Relay restart to load updated environment)
    $envDual = @{
        AINOTIFY_LISTEN = "127.0.0.1:$port"
        AINOTIFY_DB = $dbPath
        AINOTIFY_READER_TOKEN = "$oldReader,$newReader"
        AINOTIFY_INBOX_TOKEN = "$oldInbox,$newInbox"
        AINOTIFY_WRITERS = $writerMapRotated
    }
    $procDual = Start-Process -FilePath $RelayExe -Environment $envDual -PassThru -WindowStyle Hidden
    try {
        Wait-Health $url | Out-Null
        # Both old and new reader succeed
        $null = Invoke-RestMethod -NoProxy "$url/v1/events?after=0" -Headers @{Authorization="Bearer $oldReader"}
        $null = Invoke-RestMethod -NoProxy "$url/v1/events?after=0" -Headers @{Authorization="Bearer $newReader"}
        # Both old and new inbox succeed
        $null = Invoke-RestMethod -NoProxy "$url/v1/inbox/changes?after=0" -Headers @{Authorization="Bearer $oldInbox"}
        $null = Invoke-RestMethod -NoProxy "$url/v1/inbox/changes?after=0" -Headers @{Authorization="Bearer $newInbox"}
        Write-Host "PASS: Dual-credential transition accepted both old and new tokens"
    } finally {
        Stop-Process -Id $procDual.Id -Force -ErrorAction SilentlyContinue
        $procDual.WaitForExit(3000) | Out-Null
    }

    # Phase 2: Revocation of old tokens (requires Relay restart with new token set)
    $envRevoked = @{
        AINOTIFY_LISTEN = "127.0.0.1:$port"
        AINOTIFY_DB = $dbPath
        AINOTIFY_READER_TOKEN = $newReader
        AINOTIFY_INBOX_TOKEN = $newInbox
        AINOTIFY_WRITERS = (@{ win = $newWriter } | ConvertTo-Json -Compress)
    }
    $procRevoked = Start-Process -FilePath $RelayExe -Environment $envRevoked -PassThru -WindowStyle Hidden
    try {
        Wait-Health $url | Out-Null
        # Old reader rejected (401)
        $rejReader = Invoke-WebRequest -NoProxy "$url/v1/events?after=0" -Headers @{Authorization="Bearer $oldReader"} -SkipHttpErrorCheck
        if ($rejReader.StatusCode -ne 401) { throw "Old reader token was NOT revoked!" }
        # New reader accepted (200)
        $accReader = Invoke-WebRequest -NoProxy "$url/v1/events?after=0" -Headers @{Authorization="Bearer $newReader"}
        if ($accReader.StatusCode -ne 200) { throw "New reader token failed!" }

        # Old inbox rejected (401)
        $rejInbox = Invoke-WebRequest -NoProxy "$url/v1/inbox/changes?after=0" -Headers @{Authorization="Bearer $oldInbox"} -SkipHttpErrorCheck
        if ($rejInbox.StatusCode -ne 401) { throw "Old inbox token was NOT revoked!" }
        # New inbox accepted (200)
        $accInbox = Invoke-WebRequest -NoProxy "$url/v1/inbox/changes?after=0" -Headers @{Authorization="Bearer $newInbox"}
        if ($accInbox.StatusCode -ne 200) { throw "New inbox token failed!" }

        Write-Host "PASS: Credential revocation rejected old tokens with 401 and accepted new tokens"
    } finally {
        Stop-Process -Id $procRevoked.Id -Force -ErrorAction SilentlyContinue
        $procRevoked.WaitForExit(3000) | Out-Null
    }

    Write-Host "[7/7] Verifying live FCM HTTP v1 gateway dispatch, message ID receipt, and token unregistration..."
    $fcmPort = Get-FreePort
    $fcmListener = [System.Net.HttpListener]::new()
    $fcmListener.Prefixes.Add("http://127.0.0.1:$fcmPort/")
    $fcmListener.Start()
    $fcmCaptured = [System.Collections.Generic.List[object]]::new()
    $contextTask = $fcmListener.GetContextAsync()

    $fcmDb = Join-Path $scratch "fcm-live.sqlite3"
    $fcmEnv = @{
        AINOTIFY_LISTEN = "127.0.0.1:$port"
        AINOTIFY_DB = $fcmDb
        AINOTIFY_READER_TOKEN = $newReader
        AINOTIFY_INBOX_TOKEN = $newInbox
        AINOTIFY_WRITERS = (@{ win = $newWriter } | ConvertTo-Json -Compress)
        AINOTIFY_FCM_PROJECT = "test-fcm-project"
        AINOTIFY_FCM_GATEWAY_URL = "http://127.0.0.1:$fcmPort"
        AINOTIFY_FCM_TOKEN = "test-mock-bearer-token"
    }
    $procFcm = Start-Process -FilePath $RelayExe -Environment $fcmEnv -PassThru -WindowStyle Hidden
    try {
        Wait-Health $url | Out-Null

        # 1. Register valid FCM device
        $devFcm = @{ token = "valid-fcm-token-1111"; device_type = "fcm"; app_id = "test-fid-001" } | ConvertTo-Json
        Invoke-RestMethod -NoProxy "$url/v1/devices/register" -Method Post -Headers @{Authorization="Bearer $newInbox"} -ContentType 'application/json' -Body $devFcm | Out-Null

        # 2. Register expired/invalid FCM device
        $devInvalid = @{ token = "invalid-token-404"; device_type = "fcm"; app_id = "test-fid-002" } | ConvertTo-Json
        Invoke-RestMethod -NoProxy "$url/v1/devices/register" -Method Post -Headers @{Authorization="Bearer $newInbox"} -ContentType 'application/json' -Body $devInvalid | Out-Null

        # Post event
        $fcmEventId = [Guid]::NewGuid().ToString()
        $fcmEvent = @{
            schema_version = 1; id = $fcmEventId; tool = 'claude'; kind = 'turn.completed'
            device_name = 'Mac'; occurred_at_ms = 5000; message = "Confidential notification body"
        } | ConvertTo-Json
        Invoke-RestMethod -NoProxy "$url/v1/events" -Method Post -Headers @{Authorization="Bearer $newWriter"} -ContentType 'application/json' -Body $fcmEvent | Out-Null

        # Pump mock FCM HTTP listener requests
        for ($i = 0; $i -lt 40; $i++) {
            while ($contextTask.IsCompleted) {
                $ctx = $contextTask.Result
                $req = $ctx.Request
                $auth = $req.Headers["Authorization"]
                $reader = [System.IO.StreamReader]::new($req.InputStream)
                $bodyText = $reader.ReadToEnd()
                $json = $bodyText | ConvertFrom-Json
                $fcmCaptured.Add(@{ Auth = $auth; Body = $json })

                if ($auth -ne "Bearer test-mock-bearer-token") {
                    $ctx.Response.StatusCode = 401
                } elseif ($json.message.token -eq "invalid-token-404") {
                    $ctx.Response.StatusCode = 404
                    $respBytes = [System.Text.Encoding]::UTF8.GetBytes('{"error": {"code": 404, "message": "Requested entity not found", "details": [{"errorCode": "UNREGISTERED"}]}}')
                    $ctx.Response.OutputStream.Write($respBytes, 0, $respBytes.Length)
                } else {
                    $ctx.Response.StatusCode = 200
                    $respBytes = [System.Text.Encoding]::UTF8.GetBytes('{"name": "projects/test-fcm-project/messages/fcm-live-receipt-001"}')
                    $ctx.Response.OutputStream.Write($respBytes, 0, $respBytes.Length)
                }
                $ctx.Response.Close()
                $contextTask = $fcmListener.GetContextAsync()
            }
            Start-Sleep -Milliseconds 150
            if ($fcmCaptured.Count -ge 2) { break }
        }

        # Wait for Relay background dispatcher to record results
        $acceptedFound = $false
        $unregFound = $false
        for ($i = 0; $i -lt 30; $i++) {
            $deliveries = Invoke-RestMethod -NoProxy "$url/v1/push/deliveries" -Headers @{Authorization="Bearer $newReader"}
            $acc = $deliveries.deliveries | Where-Object { $_.token_mask -eq '***1111' -and $_.status -eq 'accepted' }
            $unreg = $deliveries.deliveries | Where-Object { $_.token_mask -eq '***-404' -and $_.status -eq 'unregistered' }
            if ($acc -and $unreg) {
                $acceptedFound = $true
                $unregFound = $true
                if ($acc.gateway_id -ne "projects/test-fcm-project/messages/fcm-live-receipt-001") {
                    throw "Unexpected gateway_id: $($acc.gateway_id)"
                }
                break
            }
            Start-Sleep -Milliseconds 200
        }
        if (-not $acceptedFound) { throw "FCM valid token delivery was not accepted by gateway" }
        if (-not $unregFound) { throw "FCM invalid token delivery was not marked unregistered" }

        # Verify device list no longer contains invalid-token-404
        $activeDevs = Invoke-RestMethod -NoProxy "$url/v1/devices" -Headers @{Authorization="Bearer $newReader"}
        $hasInvalid = $activeDevs.devices | Where-Object { $_.token_mask -eq '***-404' }
        if ($hasInvalid) { throw "Invalid token was not automatically removed from push_devices" }

        # Verify push payload captured by mock gateway contains ONLY event_id and NO message text
        if ($fcmCaptured.Count -eq 0) { throw "Mock FCM gateway captured zero requests" }
        foreach ($cap in $fcmCaptured) {
            if ($cap.Auth -ne "Bearer test-mock-bearer-token") { throw "Missing/invalid Bearer token header" }
            if (-not $cap.Body.message.data.event_id) { throw "Push payload missing event_id" }
            if ($cap.Body.message.data.message) { throw "Push payload leaked confidential message text!" }
            $rawCap = $cap.Body | ConvertTo-Json -Depth 5 -Compress
            if ($rawCap.Contains("Confidential notification body")) { throw "Message body leaked in FCM wire payload!" }
        }

        Write-Host "PASS: Live FCM HTTP v1 dispatch accepted, gateway receipt recorded, and invalid token unregistered"
    } finally {
        Stop-Process -Id $procFcm.Id -Force -ErrorAction SilentlyContinue
        $procFcm.WaitForExit(3000) | Out-Null
        $fcmListener.Stop()
        $fcmListener.Close()
    }

    Write-Host "`nALL RELAY DRILL AND ROTATION CHECKS PASSED!"
} finally {
    Remove-Item -Recurse -Force $scratch -ErrorAction SilentlyContinue
}
