[CmdletBinding()]
param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]] $GodotArgs
)

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = (Resolve-Path (Join-Path $ScriptDir "..\..")).Path
$GodotExe = $env:GODOT_EXE
if ([string]::IsNullOrWhiteSpace($GodotExe)) {
    $GodotExe = Join-Path $ScriptDir "Godot_v4.6.3-stable_win64.exe"
}
if (-not (Test-Path -LiteralPath $GodotExe)) {
    $SharedWorkspaceExe = Join-Path $ProjectRoot "..\..\tools\godot\Godot_v4.6.3-stable_win64.exe"
    if (Test-Path -LiteralPath $SharedWorkspaceExe) {
        $GodotExe = (Resolve-Path -LiteralPath $SharedWorkspaceExe).Path
    }
}

if (-not (Test-Path -LiteralPath $GodotExe)) {
    throw "Godot editor executable not found: $GodotExe"
}

& $GodotExe --path $ProjectRoot --editor @GodotArgs
exit $LASTEXITCODE
