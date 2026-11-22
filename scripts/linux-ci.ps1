#requires -Version 7.4
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$SourceRoot,
    [Parameter(Mandatory)][string]$OutputDir,
    [string]$Image = 'rust:1.97-bookworm'
)

$ErrorActionPreference = 'Stop'
[IO.Directory]::CreateDirectory($OutputDir) | Out-Null
$mounts = @(
    '--mount', "type=bind,src=$(Join-Path $SourceRoot 'ai-notify-agent'),dst=/source/agent,readonly",
    '--mount', "type=bind,src=$(Join-Path $SourceRoot 'ai-notify-relay'),dst=/source/relay,readonly",
    '--mount', "type=bind,src=$PSScriptRoot,dst=/source/ci,readonly",
    '--mount', "type=bind,src=$OutputDir,dst=/output"
)
docker run --rm @mounts -e CARGO_TARGET_DIR=/tmp/ainotify-target $Image bash /source/ci/linux-smoke.sh
if ($LASTEXITCODE) { throw 'Local Linux build or smoke check failed.' }
