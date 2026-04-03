# surf-top.ps1 — top pane (~60 %): custom REPL that executes forwarded commands
#
# This pane owns the real shell session.  It polls a shared flag file;
# when the middle pane deposits a command there, we execute it here and
# publish the new $PWD back so the middle pane can follow.

param(
    [string]$StateDir,
    [string]$StartDir
)

Set-Location $StartDir

# Source the user's profile so aliases/functions are available in this pane
if (Test-Path $PROFILE) { . $PROFILE }

$CmdFile      = Join-Path $StateDir "cmd.txt"
$FlagFile     = Join-Path $StateDir "cmd_ready.flag"
$BusyFile     = Join-Path $StateDir "busy.flag"
$PwdFile      = Join-Path $StateDir "pwd.txt"
$RefreshFile  = Join-Path $StateDir "refresh.flag"

function Publish-Pwd {
    $PWD.Path | Set-Content $PwdFile -Encoding UTF8 -Force
}

Publish-Pwd

# Minimal status line so the pane doesn't look abandoned
function Show-TopPrompt {
    Write-Host "`n" -NoNewline
    Write-Host (Split-Path $PWD -Leaf) -ForegroundColor DarkGray -NoNewline
    Write-Host " ▶ " -ForegroundColor DarkGray -NoNewline
}

Write-Host "surf output pane — type commands in the prompt pane below" `
    -ForegroundColor DarkGray
Write-Host ""

# ── Custom REPL ────────────────────────────────────────────────────────────
while ($true) {
    if (Test-Path $FlagFile) {
        # Signal busy so the middle pane can show a spinner (optional)
        [System.IO.File]::WriteAllText($BusyFile, "")

        $cmd = (Get-Content $CmdFile -Raw -Encoding UTF8 -ErrorAction SilentlyContinue) -replace "`r`n","`n"
        Remove-Item $FlagFile -Force -ErrorAction SilentlyContinue

        $cmd = $cmd.Trim()
        if ($cmd) {
            Show-TopPrompt
            Write-Host $cmd -ForegroundColor White
            Write-Host ""

            try {
                Invoke-Expression $cmd
            } catch {
                Write-Host "Error: $_" -ForegroundColor Red
            }

            Publish-Pwd
            [System.IO.File]::WriteAllText($RefreshFile, "")
        }

        Remove-Item $BusyFile -Force -ErrorAction SilentlyContinue
    }

    Start-Sleep -Milliseconds 50
}
