[CmdletBinding()]
param(
  [string]$ProjectRoot = (Get-Location).Path,
  [string]$NodeExe = "C:\Program Files\nodejs\node.exe",
  [string]$HvigorJs = "D:\Huawei\DevEco Studio\tools\hvigor\hvigor\bin\hvigor.js",
  [string]$HdcExe = "D:\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe",
  [string]$Target,
  [string]$BundleName = "com.dreamflytech.cloudrs",
  [string]$AbilityName = "EntryAbility",
  [string]$HapPath,
  [switch]$NoDaemon,
  [switch]$NoStart
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Fail($msg){ throw "[harmonyos-install] $msg" }

if (-not (Test-Path $NodeExe)) { Fail "Node executable not found: $NodeExe" }
if (-not (Test-Path $HvigorJs)) { Fail "hvigor.js not found: $HvigorJs" }
if (-not (Test-Path $HdcExe)) { Fail "hdc.exe not found: $HdcExe" }

Set-Location -Path $ProjectRoot

$args = @($HvigorJs, 'assembleHap')
if ($NoDaemon.IsPresent) { $args += '--no-daemon' }
& $NodeExe @args
if ($LASTEXITCODE -ne 0) { Fail "assembleHap failed, exit code: $LASTEXITCODE" }

if (-not $Target) {
  $targets = & $HdcExe list targets | Where-Object { $_ -match '\S' }
  if (!$targets) { Fail 'No hdc target found. Start emulator or connect a device.' }
  $Target = ($targets | Select-Object -First 1).Trim()
}

if (-not $HapPath) {
  $defaultHap = Join-Path $ProjectRoot 'entry\build\default\outputs\default\entry-default-signed.hap'
  if (Test-Path $defaultHap) {
    $HapPath = $defaultHap
  } else {
    $fallback = Get-ChildItem -Path (Join-Path $ProjectRoot 'entry\build\default\outputs\default') -Filter 'entry-default-signed.hap' -ErrorAction SilentlyContinue |
      Sort-Object LastWriteTime -Descending |
      Select-Object -First 1
    if (-not $fallback) { Fail 'entry-default-signed.hap not found. Run assembleHap first.' }
    $HapPath = $fallback.FullName
  }
}
if (-not (Test-Path $HapPath)) { Fail "HAP not found: $HapPath" }

& $HdcExe -t $Target install $HapPath
if ($LASTEXITCODE -ne 0) { Fail "hdc install failed, exit code: $LASTEXITCODE" }

if (-not $NoStart.IsPresent) {
  & $HdcExe -t $Target shell aa start -b $BundleName -a $AbilityName
  if ($LASTEXITCODE -ne 0) { Fail "aa start failed, exit code: $LASTEXITCODE" }
}

Write-Output "INSTALL FLOW FINISHED"
Write-Output "Target: $Target"
Write-Output "HAP: $((Resolve-Path $HapPath).Path)"
Write-Output "Started: $(-not $NoStart.IsPresent)"
