[CmdletBinding()]
param(
  [string]$ProjectRoot = (Get-Location).Path,
  [string]$NodeExe = "C:\Program Files\nodejs\node.exe",
  [string]$HvigorJs = "D:\Huawei\DevEco Studio\tools\hvigor\hvigor\bin\hvigor.js",
  [string]$HdcExe = "D:\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe",
  [string]$Target,
  [string]$BundleName = "com.dreamflytech.cloudrs",
  [string]$HapPath,
  [string]$OutputDir = "D:\Code\HarmonyOSNext\DevEcoStudioProjects\Cloudrs\harmonyos-debug-pipeline\artifacts",
  [int]$LogTailLines = 400,
  [switch]$NoDaemon
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Fail($msg){ throw "[harmonyos-debug] $msg" }

if (-not (Test-Path $NodeExe)) { Fail "Node executable 不存在: $NodeExe" }
if (-not (Test-Path $HvigorJs)) { Fail "hvigor.js 不存在: $HvigorJs" }
if (-not (Test-Path $HdcExe)) { Fail "hdc.exe 不存在: $HdcExe" }

New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
Set-Location -Path $ProjectRoot

$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$summary = [ordered]@{
  Timestamp = $timestamp
  ProjectRoot = (Resolve-Path $ProjectRoot).Path
  Target = $null
  HapPath = $null
  InstallExitCode = $null
  SnapshotPath = $null
}

$args = @($HvigorJs, 'assembleHap')
if ($NoDaemon.IsPresent) { $args += '--no-daemon' }
& $NodeExe @args
if ($LASTEXITCODE -ne 0) { Fail "assembleHap 失败，退出码: $LASTEXITCODE" }

if (-not $Target) {
  $targets = & $HdcExe list targets | Where-Object { $_ -match '\S' }
  if (!$targets) { Fail '未发现 hdc 设备，请确认模拟器/真机已连接' }
  $Target = ($targets | Select-Object -First 1).Trim()
}
$summary.Target = $Target

if (-not $HapPath) {
  $defaultHap = Join-Path $ProjectRoot 'entry\build\default\outputs\default\entry-default-signed.hap'
  if (Test-Path $defaultHap) {
    $HapPath = $defaultHap
  } else {
    $fallback = Get-ChildItem -Path (Join-Path $ProjectRoot 'entry\build\default\outputs\default') -Filter 'entry-default-signed.hap' -ErrorAction SilentlyContinue |
      Sort-Object LastWriteTime -Descending |
      Select-Object -First 1
    if (-not $fallback) { Fail '未找到 entry-default-signed.hap，请先运行 assembleHap' }
    $HapPath = $fallback.FullName
  }
}
if (-not (Test-Path $HapPath)) { Fail "HAP 文件不存在: $HapPath" }
$summary.HapPath = (Resolve-Path $HapPath).Path

& $HdcExe -t $Target install $HapPath
$summary.InstallExitCode = $LASTEXITCODE
if ($LASTEXITCODE -ne 0) { Fail "hdc install 失败，退出码: $LASTEXITCODE" }

$hilogFile = Join-Path $OutputDir "hilog-$timestamp.txt"
& $HdcExe -t $Target shell hilog -x -t app > $hilogFile

$remoteShot = "/data/local/tmp/${BundleName}-${timestamp}.jpeg"
$localShot = Join-Path $OutputDir "screenshot-${timestamp}.jpeg"
& $HdcExe -t $Target shell "snapshot_display -f $remoteShot"
if ($LASTEXITCODE -ne 0) { Fail "snapshot_display 失败，退出码: $LASTEXITCODE" }
& $HdcExe -t $Target file recv $remoteShot $localShot
& $HdcExe -t $Target shell "rm $remoteShot"
$summary.SnapshotPath = $localShot

$summaryFile = Join-Path $OutputDir "debug-summary-$timestamp.json"
$summary | ConvertTo-Json | Out-File -FilePath $summaryFile -Encoding utf8

Write-Output "DEBUG FLOW FINISHED"
Write-Output "Install exit: $($summary.InstallExitCode)"
Write-Output "HAP: $($summary.HapPath)"
Write-Output "Hilog: $hilogFile"
Write-Output "Screenshot: $localShot"
Write-Output "Summary: $summaryFile"
