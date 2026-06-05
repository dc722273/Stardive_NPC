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

$HasExplicitPath = $GodotArgs -contains "--path"
$ProjectNeutralArgs = @("--version", "--help", "-h", "--project-manager")
$UsesProjectNeutralMode = $false
foreach ($Arg in $GodotArgs) {
    if ($ProjectNeutralArgs -contains $Arg) {
        $UsesProjectNeutralMode = $true
        break
    }
}

if ($HasExplicitPath -or $UsesProjectNeutralMode) {
    & $GodotExe @GodotArgs
} else {
    & $GodotExe --path $ProjectRoot @GodotArgs
}

exit $LASTEXITCODE
