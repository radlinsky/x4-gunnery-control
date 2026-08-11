[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

function Fail([string]$Message) {
    throw "Windows contract failure: $Message"
}

$repo = Split-Path -Parent $PSScriptRoot
$agent = Join-Path $repo '.agents/release.agent.md'
$prompt = Join-Path $repo '.github/prompts/release.prompt.md'
$settings = Join-Path $repo '.claude/settings.json'
$codexHooks = Join-Path $repo '.codex/hooks.json'

if (-not (Test-Path -LiteralPath $prompt -PathType Leaf)) {
    Fail 'release prompt is not a regular file'
}
if ((Get-Item -LiteralPath $prompt).Attributes -band [IO.FileAttributes]::ReparsePoint) {
    Fail 'release prompt must not be a symlink or other reparse point'
}
if ([Convert]::ToBase64String([IO.File]::ReadAllBytes($agent)) -cne
    [Convert]::ToBase64String([IO.File]::ReadAllBytes($prompt))) {
    Fail 'release prompt is not byte-identical to .agents/release.agent.md'
}
if ((git -C $repo ls-files -s -- .github/prompts/release.prompt.md) -notmatch '^100644 ') {
    Fail 'release prompt is not tracked as mode 100644'
}

$parsedSettings = Get-Content -LiteralPath $settings -Raw | ConvertFrom-Json
$hook = $parsedSettings.hooks.PostToolUse | Where-Object { $_.matcher -eq 'Edit|Write|NotebookEdit' } | Select-Object -First 1
if ($null -eq $hook -or $null -eq $hook.hooks -or [string]::IsNullOrWhiteSpace($hook.hooks[0].command)) {
    Fail 'settings JSON has no executable PostToolUse reload-advice hook'
}
$parsedCodexHooks = Get-Content -LiteralPath $codexHooks -Raw | ConvertFrom-Json
$codexHook = $parsedCodexHooks.hooks.PostToolUse | Where-Object { $_.matcher -match 'apply_patch' } | Select-Object -First 1
if ($null -eq $codexHook -or $null -eq $codexHook.hooks -or
    $codexHook.hooks[0].command -notmatch '\.agents/hooks/reload-advice\.sh' -or
    $codexHook.hooks[0].commandWindows -notmatch '\.agents/hooks/reload-advice\.sh') {
    Fail 'Codex hooks JSON has no cross-platform PostToolUse reload-advice hook'
}

$spaceRoot = Join-Path ([IO.Path]::GetTempPath()) ("x4gc contract with spaces " + [guid]::NewGuid())
try {
    New-Item -ItemType Directory -Path (Join-Path $spaceRoot '.agents/hooks') -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $repo '.agents/hooks/reload-advice.sh') -Destination (Join-Path $spaceRoot '.agents/hooks/reload-advice.sh')
    # Git Bash receives Windows environment values unchanged, but Bash cannot
    # open C:\... paths. Convert the test root before expanding the parsed hook.
    $bashRoot = (& bash -lc "cygpath -u -- `"$spaceRoot`"").Trim()
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($bashRoot)) {
        Fail 'could not convert the spaced temporary project path for Git Bash'
    }
    $oldClaudeProjectDir = $env:CLAUDE_PROJECT_DIR
    try {
        $env:CLAUDE_PROJECT_DIR = $bashRoot
        $payloadPath = "$bashRoot/ui/gunnery_control.lua"
        $payload = '{"tool_input":{"file_path":"' + $payloadPath + '"}}'
        $hookOutput = $payload | & bash -c $hook.hooks[0].command 2>&1
        if ($LASTEXITCODE -ne 0 -or ($hookOutput -join "`n") -notmatch 'Reload UI') {
            Fail "quoted reload hook did not execute from a spaced project path: $hookOutput"
        }

        & git -C $spaceRoot init --quiet
        if ($LASTEXITCODE -ne 0) {
            Fail 'could not initialize temporary Git root for the Codex hook contract'
        }
        $codexPayload = '{"tool_input":{"command":"*** Begin Patch\n*** Update File: ui/gunnery_control.lua\n*** End Patch"}}'
        Push-Location $spaceRoot
        try {
            $codexOutput = $codexPayload | & cmd.exe /d /s /c $codexHook.hooks[0].commandWindows 2>&1
        }
        finally {
            Pop-Location
        }
        if ($LASTEXITCODE -ne 0 -or ($codexOutput -join "`n") -notmatch 'Reload UI') {
            Fail "registered Codex Windows hook did not execute from a spaced project path: $codexOutput"
        }
    }
    finally {
        if ($null -eq $oldClaudeProjectDir) {
            Remove-Item Env:CLAUDE_PROJECT_DIR -ErrorAction SilentlyContinue
        }
        else {
            $env:CLAUDE_PROJECT_DIR = $oldClaudeProjectDir
        }
    }

    foreach ($launcher in @('launch-x4-dev.bat', 'launch-x4-test-lab-dev.bat')) {
        Copy-Item -LiteralPath (Join-Path $repo "scripts/$launcher") -Destination (Join-Path $spaceRoot "scripts/$launcher")
    }
    $oldPause = $env:X4GC_NO_PAUSE
    $oldExe = $env:X4GC_EXE
    $oldRoot = $env:X4GC_GAME_ROOT
    try {
        $env:X4GC_NO_PAUSE = '1'
        Remove-Item Env:X4GC_EXE -ErrorAction SilentlyContinue
        Remove-Item Env:X4GC_GAME_ROOT -ErrorAction SilentlyContinue
        foreach ($launcher in @('launch-x4-dev.bat', 'launch-x4-test-lab-dev.bat')) {
            $path = Join-Path $spaceRoot "scripts/$launcher"
            $output = & cmd.exe /d /c "call `"$path`" `"C:\x4gc-definitely-missing\X4.exe`"" 2>&1
            if ($LASTEXITCODE -ne 2) {
                Fail "$launcher returned $LASTEXITCODE instead of deterministic missing-X4 exit 2"
            }
            if (($output -join "`n") -notmatch 'ERROR: X4.exe was not found.') {
                Fail "$launcher did not report its deterministic missing-X4 error"
            }
        }
    }
    finally {
        $env:X4GC_NO_PAUSE = $oldPause
        $env:X4GC_EXE = $oldExe
        $env:X4GC_GAME_ROOT = $oldRoot
    }
}
finally {
    Remove-Item -LiteralPath $spaceRoot -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host 'Windows checkout and launcher contracts passed'
