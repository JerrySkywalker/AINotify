#requires -Version 7.4
[CmdletBinding()]
param()

$jdkRoot = Join-Path $env:LOCALAPPDATA 'AINotify/toolchains'
$jdk = Get-ChildItem -LiteralPath $jdkRoot -Directory -Filter 'jdk-17*' -ErrorAction SilentlyContinue |
    Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'bin/javac.exe') } |
    Sort-Object Name -Descending |
    Select-Object -First 1
$sdk = Join-Path $env:LOCALAPPDATA 'Android/Sdk'
$rustupBin = Join-Path $env:USERPROFILE '.cargo/bin'

if (-not $jdk) { throw "JDK 17 was not found under $jdkRoot." }
if (-not (Test-Path -LiteralPath (Join-Path $sdk 'platforms/android-36/android.jar'))) {
    throw "Android SDK Platform 36 was not found under $sdk."
}
if (-not (Test-Path -LiteralPath (Join-Path $rustupBin 'rustup.exe'))) {
    throw "Rustup was not found under $rustupBin."
}

$env:JAVA_HOME = $jdk.FullName
$env:ANDROID_HOME = $sdk
$env:RUSTUP_TOOLCHAIN = '1.97.0-x86_64-pc-windows-msvc'
$toolPaths = @(
    $rustupBin
    (Join-Path $env:JAVA_HOME 'bin')
    (Join-Path $sdk 'platform-tools')
    (Join-Path $sdk 'emulator')
    (Join-Path $sdk 'cmdline-tools/latest/bin')
)
$pathEntries = $env:Path -split ';' | Where-Object {
    $_ -and $_.Replace('/', '\').TrimEnd('\') -notin $toolPaths
}
$env:Path = ($toolPaths + $pathEntries) -join ';'

# Gradle's JVM uses system properties for the HTTP proxy.
if ($env:GRADLE_OPTS -notmatch '-Dhttps\.proxyHost=') {
    $maven = [uri]'https://dl.google.com/dl/android/maven2/'
    $proxy = [Net.WebRequest]::GetSystemWebProxy().GetProxy($maven)
    if ($proxy -and $proxy -ne $maven -and $proxy.Scheme -eq 'http') {
        $proxyOptions = "-Dhttp.proxyHost=$($proxy.Host) -Dhttp.proxyPort=$($proxy.Port)"
        $proxyOptions += " -Dhttps.proxyHost=$($proxy.Host) -Dhttps.proxyPort=$($proxy.Port)"
        $env:GRADLE_OPTS = ($env:GRADLE_OPTS, $proxyOptions -join ' ').Trim()
    }
}
