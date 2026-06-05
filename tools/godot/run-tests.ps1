[CmdletBinding()]
param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]] $GodotArgs
)

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = (Resolve-Path (Join-Path $ScriptDir "..\..")).Path
$GodotExe = $env:GODOT_CONSOLE_EXE
if ([string]::IsNullOrWhiteSpace($GodotExe)) {
    $GodotExe = Join-Path $ScriptDir "Godot_v4.6.3-stable_win64_console.exe"
}
if (-not (Test-Path -LiteralPath $GodotExe)) {
    $SharedWorkspaceExe = Join-Path $ProjectRoot "..\..\tools\godot\Godot_v4.6.3-stable_win64_console.exe"
    if (Test-Path -LiteralPath $SharedWorkspaceExe) {
        $GodotExe = (Resolve-Path -LiteralPath $SharedWorkspaceExe).Path
    }
}

if (-not (Test-Path -LiteralPath $GodotExe)) {
    throw "Godot console executable not found: $GodotExe"
}

$Output = & $GodotExe --headless --path $ProjectRoot --script tests/run_tests.gd @GodotArgs 2>&1
$ExitCode = $LASTEXITCODE
$Output | ForEach-Object { Write-Host $_ }

$OutputText = ($Output | Out-String)
if ($ExitCode -ne 0 -or $OutputText -match "SCRIPT ERROR|ERROR:") {
    exit 1
}

exit 0
