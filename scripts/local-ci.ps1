#requires -Version 7.4
[CmdletBinding()]
param(
    [string]$SourceRoot = (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)),
    [string]$SdkRoot = $env:ANDROID_HOME,
    [string]$JavaHome = $env:JAVA_HOME,
    [Parameter(Mandatory)][ValidatePattern('^emulator-\d+$')][string]$PhoneSerial,
    [Parameter(Mandatory)][ValidatePattern('^emulator-\d+$')][string]$WearSerial,
    [ValidateSet('direct','paired')][string]$WearMode = 'direct',
    [switch]$SkipBuild,
    [switch]$DebugRust,
    [string]$GradleInitScript,
    [switch]$Offline,
    [switch]$SkipDesktop,
    [switch]$Linux,
    [string]$RelayExe
)

$ErrorActionPreference = 'Stop'
if ($PhoneSerial -eq $WearSerial) { throw 'Phone and watch must be distinct AVDs.' }
$agent = Join-Path $SourceRoot 'ai-notify-agent'
$relay = Join-Path $SourceRoot 'ai-notify-relay'
$android = Join-Path $SourceRoot 'ai-notify-android'
if (-not $SkipBuild) {
    & (Join-Path $relay 'scripts/local-ci.ps1')
    & (Join-Path $agent 'scripts/local-ci.ps1')
    & (Join-Path $android 'scripts/local-ci.ps1') -SdkRoot $SdkRoot -JavaHome $JavaHome -InitScript $GradleInitScript -Offline:$Offline
}
$out = Join-Path (Split-Path -Parent $PSScriptRoot) ('build/ci/' + [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfffZ'))
[IO.Directory]::CreateDirectory($out) | Out-Null
if ($Linux) {
    & (Join-Path $PSScriptRoot 'linux-ci.ps1') -SourceRoot $SourceRoot -OutputDir (Join-Path $out 'linux')
}
$profile = if ($DebugRust) { 'debug' } else { 'release' }
if (-not $RelayExe) { $RelayExe = Join-Path $relay "target/$profile/ai-notify-relay.exe" }
& (Join-Path $PSScriptRoot 'drill-relay-v0.4.1.ps1') -RelayExe $RelayExe

$arguments = @{
    AgentRoot = $agent
    RelayRoot = $relay
    AndroidRoot = $android
    SdkRoot = $SdkRoot
    PhoneSerial = $PhoneSerial
    WearSerial = $WearSerial
    WearMode = $WearMode
    OutputDir = $out
    DebugRust = $DebugRust
    SkipDesktop = $SkipDesktop
    RelayExe = $RelayExe
}
& (Join-Path $PSScriptRoot 'e2e.ps1') @arguments
$artifacts = Join-Path $out 'artifacts'
[IO.Directory]::CreateDirectory($artifacts) | Out-Null
$files = @(
    (Join-Path $agent "target/$profile/ai-notify-agent.exe"),
    (Join-Path $agent "target/$profile/ai-notify-desktop.exe"),
    $RelayExe,
    (Join-Path $android 'mobile/build/outputs/apk/debug/mobile-debug.apk'),
    (Join-Path $android 'wear/build/outputs/apk/debug/wear-debug.apk')
)
foreach ($file in $files) { Copy-Item -LiteralPath $file -Destination $artifacts }
if ($Linux) {
    foreach ($name in 'ai-notify-agent','ai-notify-relay') {
        Copy-Item -LiteralPath (Join-Path $out "linux/$name") -Destination (Join-Path $artifacts "$name-linux-x64")
    }
}
Get-ChildItem -LiteralPath $artifacts -File | Sort-Object Name | ForEach-Object {
    $hash = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    "$hash  $($_.Name)"
} | Set-Content -LiteralPath (Join-Path $artifacts 'SHA256SUMS') -Encoding ascii

"Local CI evidence: $out"
