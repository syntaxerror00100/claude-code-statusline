# Installs claude-code-statusline from PowerShell by running install.sh with Git Bash.
#
#   powershell -ExecutionPolicy Bypass -File .\install.ps1

$ErrorActionPreference = 'Stop'

$bash = @(
  "$env:ProgramFiles\Git\bin\bash.exe",
  "${env:ProgramFiles(x86)}\Git\bin\bash.exe",
  "$env:LOCALAPPDATA\Programs\Git\bin\bash.exe"
) | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1

if (-not $bash) {
  throw 'Git Bash not found. Install Git for Windows (https://git-scm.com/download/win) and re-run.'
}

& $bash (Join-Path $PSScriptRoot 'install.sh')
exit $LASTEXITCODE
