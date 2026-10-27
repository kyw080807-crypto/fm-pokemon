# Force recompile, run Game.exe in debug mode, then print what the run logged.
#   powershell -NoProfile -ExecutionPolicy Bypass -File tools/run_debug.ps1 [-RecompilePbs] [-Smoke] [-TimeoutSec 600]
# -Smoke writes logs/smoke.flag for the [900] FM Debug plugin (not implemented yet).
param(
  [switch]$RecompilePbs,
  [switch]$Smoke,
  [int]$TimeoutSec = 600
)
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
Set-Location $root

if (Get-Process -Name RPGXP -ErrorAction SilentlyContinue) {
  Write-Output 'ABORT: RPG Maker XP is running. Close it first (it overwrites Data/ on save).'
  exit 2
}
if (Get-Process -Name Game -ErrorAction SilentlyContinue | Where-Object { $_.Path -like "$root*" }) {
  Write-Output 'ABORT: Game.exe from this project is already running.'
  exit 2
}
if (-not (Test-Path 'Game.exe')) {
  Write-Output "ABORT: Game.exe not found in $root"
  exit 2
}

Remove-Item 'Data/PluginScripts.rxdata' -ErrorAction SilentlyContinue
Write-Output 'Deleted Data/PluginScripts.rxdata (plugins will recompile).'
if ($RecompilePbs) {
  # messages*.dat hold extracted text, not PBS output: keep them.
  Get-ChildItem 'Data' -Filter '*.dat' | Where-Object { $_.Name -notlike 'messages*' } | Remove-Item
  Write-Output 'Deleted Data/*.dat except messages*.dat (PBS will recompile).'
}

New-Item -ItemType Directory -Force 'logs' | Out-Null
$log = 'logs/fm_runtime.log'
$startLine = 0
if (Test-Path $log) { $startLine = (Get-Content $log -Encoding UTF8 | Measure-Object -Line).Lines }
if ($Smoke) { Set-Content 'logs/smoke.flag' -Value (Get-Date -Format o) -Encoding utf8 }
$started = Get-Date

$p = Start-Process -FilePath (Join-Path $root 'Game.exe') -ArgumentList 'debug' -WorkingDirectory $root -PassThru
Write-Output "Game.exe debug started (pid $($p.Id)). Waiting for the window to close (timeout ${TimeoutSec}s)..."
if (-not $p.WaitForExit($TimeoutSec * 1000)) {
  Write-Output 'TIMEOUT: game still running; stopping it.'
  Stop-Process -Id $p.Id -Force
}
Remove-Item 'logs/smoke.flag' -ErrorAction SilentlyContinue
Write-Output "Exit code: $($p.ExitCode)"

Write-Output '--- logs/fm_runtime.log (this run) ---'
if (Test-Path $log) {
  Get-Content $log -Encoding UTF8 | Select-Object -Skip $startLine
} else {
  Write-Output '(no log written: FM Logger did not load - plugins may not have compiled)'
}

# errorlog.txt location differs between sources; check the project and %APPDATA%.
$candidates = @(Join-Path $root 'errorlog.txt') + @(Get-ChildItem "$env:APPDATA\*\errorlog.txt" -ErrorAction SilentlyContinue | ForEach-Object FullName)
foreach ($e in $candidates) {
  if ((Test-Path $e) -and (Get-Item $e).LastWriteTime -ge $started) {
    Write-Output "--- $e (written this run) ---"
    Get-Content $e -Encoding UTF8
  }
}
