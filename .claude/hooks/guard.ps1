# PreToolUse guard for the FM Essentials project.
# Denies: binary edits (.rxdata/.dat), core script edits (Data/Scripts/),
# edits to Data/ PBS/ Plugins/ while Game.exe or RPG Maker XP is running,
# and running scripts_extract.rb / scripts_combine.rb.
# Written for Windows PowerShell 5.1 so the project needs no Python.

$ErrorActionPreference = 'Stop'
[Console]::InputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

function Deny([string]$reason) {
  $out = @{
    hookSpecificOutput = @{
      hookEventName            = 'PreToolUse'
      permissionDecision       = 'deny'
      permissionDecisionReason = $reason
    }
  }
  $out | ConvertTo-Json -Compress -Depth 4
  exit 0
}

try {
  $payload = [Console]::In.ReadToEnd() | ConvertFrom-Json
} catch {
  exit 0  # Not our input shape; let other checks decide.
}

$projectDir = $env:CLAUDE_PROJECT_DIR
if (-not $projectDir) { $projectDir = $payload.cwd }
if (-not $projectDir) { $projectDir = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path }
$projectDir = [System.IO.Path]::GetFullPath($projectDir).TrimEnd('\', '/')

function Get-EngineProcesses {
  $found = @()
  foreach ($name in 'Game', 'RPGXP') {
    foreach ($p in @(Get-Process -Name $name -ErrorAction SilentlyContinue)) {
      $path = $null
      try { $path = $p.Path } catch {}
      # Game.exe only counts when it is this project's; RPGXP always counts.
      if ($name -eq 'RPGXP' -or ($path -and $path.StartsWith($projectDir, [StringComparison]::OrdinalIgnoreCase))) {
        $found += "$name.exe"
      }
    }
  }
  $found | Select-Object -Unique
}

$tool = [string]$payload.tool_name
$input_ = $payload.tool_input

if ($tool -in 'Bash', 'PowerShell') {
  $cmd = [string]$input_.command
  if ($cmd -match 'scripts_(extract|combine)\.rb') {
    Deny 'scripts_extract.rb / scripts_combine.rb는 사람이 직접 실행합니다 (CLAUDE.md 절대 금지).'
  }
  exit 0
}

$filePath = [string]$input_.file_path
if (-not $filePath) { $filePath = [string]$input_.notebook_path }
if (-not $filePath) { exit 0 }

if (-not [System.IO.Path]::IsPathRooted($filePath)) { $filePath = Join-Path $projectDir $filePath }
$full = [System.IO.Path]::GetFullPath($filePath)
$rel = $full
if ($full.StartsWith($projectDir + '\', [StringComparison]::OrdinalIgnoreCase)) {
  $rel = $full.Substring($projectDir.Length + 1)
}
$rel = $rel -replace '\\', '/'
$ext = [System.IO.Path]::GetExtension($full).ToLowerInvariant()

if ($ext -in '.rxdata', '.dat') {
  Deny "$rel 은(는) Ruby Marshal 바이너리입니다. 직접 편집하지 말고 RMXP(맵) 또는 PBS+컴파일(데이터)로 바꾸세요."
}
if ($rel -match '^(?i)Data/Scripts/') {
  Deny "Data/Scripts/ 는 엔진 코어(읽기 전용)입니다. Plugins/ 에서 alias로 감싸세요: $rel"
}
if ($rel -match '^(?i)(Data|PBS|Plugins)/') {
  $running = @(Get-EngineProcesses)
  if ($running.Count -gt 0) {
    Deny ("{0} 실행 중에는 {1} 을(를) 수정할 수 없습니다. 창을 닫은 뒤 다시 시도하세요." -f ($running -join ', '), $rel)
  }
}
exit 0
