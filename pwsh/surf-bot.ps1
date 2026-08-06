# surf-bot.ps1 — bottom pane (~30 %): live git log
#
# Redraws the git log when pwd.txt changes or refresh.flag is written.
# refresh.flag is created by surf-main.ps1 after each command completes,
# so there are no timer-driven redraws — mirrors surf-bot.zsh behaviour.

param(
    [string]$StateDir,
    [string]$StartDir
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$PwdFile     = Join-Path $StateDir "pwd.txt"
$RefreshFile = Join-Path $StateDir "refresh.flag"

[Console]::CursorVisible = $false
$null = Register-EngineEvent -SourceIdentifier PowerShell.Exiting -Action {
    [Console]::CursorVisible = $true
}

function Draw-GitLog {
    param([string]$Dir)

    # Query actual pane size each draw so resizes are handled correctly
    $rows = $Host.UI.RawUI.WindowSize.Height
    $cols = $Host.UI.RawUI.WindowSize.Width
    if ($rows -lt 5) { $rows = 5 }
    $rows--   # leave one line at the bottom to avoid scroll

    # Clear pane without flicker
    [Console]::SetCursorPosition(0, 0)
    $blank = ' ' * $cols
    for ($i = 0; $i -lt ($rows + 1); $i++) {
        [Console]::SetCursorPosition(0, $i)
        [Console]::Write($blank)
    }
    [Console]::SetCursorPosition(0, 0)

    $isRepo = git -C $Dir rev-parse --is-inside-work-tree 2>$null
    $useYadm = $false
    if (-not $isRepo -and (Get-Command yadm -ErrorAction SilentlyContinue)) {
        $homePath = [System.IO.Path]::GetFullPath($HOME).TrimEnd(
            [System.IO.Path]::DirectorySeparatorChar,
            [System.IO.Path]::AltDirectorySeparatorChar
        )
        $dirPath = [System.IO.Path]::GetFullPath($Dir)
        $underHome = $dirPath -eq $homePath -or
            $dirPath.StartsWith($homePath + [System.IO.Path]::DirectorySeparatorChar,
                [System.StringComparison]::OrdinalIgnoreCase)
        if ($underHome) {
            $useYadm = [bool](yadm rev-parse --is-inside-work-tree 2>$null)
        }
    }

    if (-not $isRepo -and -not $useYadm) {
        Write-Host "not a git repository: $Dir" -ForegroundColor Yellow
        return
    }

    if ($useYadm) {
        # yadm covers $HOME recursively. A regular nested repository still wins.
        $lines = yadm log --oneline --graph --decorate --all -n $rows --color=always 2>$null
    } else {
        $lines = git -C $Dir log --oneline --graph --decorate --all -n $rows --color=always 2>$null
    }
    if (-not $lines) {
        Write-Host "(no commits)" -ForegroundColor DarkGray
        return
    }

    foreach ($l in ($lines | Select-Object -First $rows)) {
        # Naive truncation to terminal width (ANSI codes count toward the limit,
        # same as cut -c in the Linux version)
        if ($l.Length -gt $cols) { $l = $l.Substring(0, $cols) }
        [Console]::WriteLine($l)
    }
}

# ── Main loop ──────────────────────────────────────────────────────────────
$lastPwd = ""

while ($true) {
    $curPwd = $StartDir
    if (Test-Path $PwdFile) {
        $r = Get-Content $PwdFile -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
        if ($r) { $curPwd = $r.Trim() }
    }

    $needsRefresh = Test-Path $RefreshFile

    if ($curPwd -ne $lastPwd -or $needsRefresh) {
        if ($needsRefresh) {
            Remove-Item $RefreshFile -Force -ErrorAction SilentlyContinue
        }
        Draw-GitLog -Dir $curPwd
        $lastPwd = $curPwd
    }

    Start-Sleep -Milliseconds 500
}
