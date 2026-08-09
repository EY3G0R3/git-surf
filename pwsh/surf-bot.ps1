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
$ThemeFile   = Join-Path $StateDir "theme.txt"

[Console]::CursorVisible = $false
$null = Register-EngineEvent -SourceIdentifier PowerShell.Exiting -Action {
    [Console]::CursorVisible = $true
}

function Get-CurrentHeadOid {
    param([string]$Dir)

    if (git -C $Dir rev-parse --is-inside-work-tree 2>$null) {
        return git -C $Dir rev-parse HEAD 2>$null
    }
    if (Get-Command yadm -ErrorAction SilentlyContinue) {
        $homePath = [System.IO.Path]::GetFullPath($HOME).TrimEnd(
            [System.IO.Path]::DirectorySeparatorChar,
            [System.IO.Path]::AltDirectorySeparatorChar
        )
        $dirPath = [System.IO.Path]::GetFullPath($Dir)
        if ($dirPath -eq $homePath -or $dirPath.StartsWith(
                $homePath + [System.IO.Path]::DirectorySeparatorChar,
                [System.StringComparison]::OrdinalIgnoreCase)) {
            return yadm rev-parse HEAD 2>$null
        }
    }
    return $null
}

function Draw-GitLog {
    param(
        [string]$Dir,
        [string]$Theme = "adaptive-diamond",
        [ValidateSet("None", "Strong", "Subtle")]
        [string]$Pulse = "None"
    )

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
        $headOid = yadm rev-parse HEAD 2>$null
        $headShort = yadm rev-parse --short HEAD 2>$null
        $mainOid = yadm rev-parse --verify refs/heads/main 2>$null
        if (-not $mainOid) {
            $mainOid = yadm rev-parse --verify refs/remotes/origin/main 2>$null
        }
        $lines = yadm log '--pretty=format:%H%x1f%C(yellow)%h%C(reset) %C(green)%>|(25)%cr%C(reset) %s %C(bold blue)<%cl>%C(reset) %C(auto)%D%C(reset)' --graph --all -n $rows --color=always 2>$null
    } else {
        $headOid = git -C $Dir rev-parse HEAD 2>$null
        $headShort = git -C $Dir rev-parse --short HEAD 2>$null
        $mainOid = git -C $Dir rev-parse --verify refs/heads/main 2>$null
        if (-not $mainOid) {
            $mainOid = git -C $Dir rev-parse --verify refs/remotes/origin/main 2>$null
        }
        $lines = git -C $Dir log '--pretty=format:%H%x1f%C(yellow)%h%C(reset) %C(green)%>|(25)%cr%C(reset) %s %C(bold blue)<%cl>%C(reset) %C(auto)%D%C(reset)' --graph --all -n $rows --color=always 2>$null
    }
    if (-not $lines) {
        Write-Host "(no commits)" -ForegroundColor DarkGray
        return
    }

    foreach ($l in ($lines | Select-Object -First $rows)) {
        $sizedHead = $false
        $separatorAt = $l.IndexOf([char]0x1f)
        if ($separatorAt -ge 0) {
            $graphAndOid = $l.Substring(0, $separatorAt)
            $rendered = $l.Substring($separatorAt + 1)
            $oidAt = $graphAndOid.Length - $headOid.Length
            if ($oidAt -ge 0) {
                $oid = $graphAndOid.Substring($oidAt)
                $graph = $graphAndOid.Substring(0, $oidAt)
                $starAt = $graph.IndexOf('*')
                $headGraph = $graph
                $mainGraph = $graph
                if ($starAt -ge 0) {
                    $headGraph = $graph.Substring(0, $starAt) + "`e[1;96m◆`e[0m" +
                        $graph.Substring($starAt + 1)
                    $mainGraph = $graph.Substring(0, $starAt) + "`e[1;32m◆`e[0m" +
                        $graph.Substring($starAt + 1)
                }
                $isHead = $oid -eq $headOid
                $isMain = $mainOid -and $oid -eq $mainOid
                if ($isHead) {
                    $label = if ($isMain) { "H+M" } else { "HEAD" }
                    $arrow = if ($isMain) { " ->  " } else { " -> " }
                    switch ($Theme) {
                        "adaptive-diamond" {
                            if ($Pulse -eq "Strong") {
                                $plain = [regex]::Replace($label + $arrow +
                                    $graph.Replace('*', '◆') + $rendered,
                                    "`e\[[0-9;]*m", "")
                                if ($plain.Length -gt $cols) { $plain = $plain.Substring(0, $cols) }
                                $l = "`e[1;30;46m" + $plain.PadRight($cols) + "`e[0m"
                                $sizedHead = $true
                            } elseif ($Pulse -eq "Subtle") {
                                $l = "`e[1;30;46m$label`e[0;97m$arrow`e[0m" +
                                    $headGraph + $rendered
                            } else {
                                $l = "`e[1;96m$label`e[0;97m$arrow`e[0m" +
                                    $headGraph + $rendered
                            }
                        }
                        "pulse-arrow" {
                            if ($Pulse -eq "Strong") {
                                $plain = [regex]::Replace($label + $arrow + $graph + $rendered,
                                    "`e\[[0-9;]*m", "")
                                if ($plain.Length -gt $cols) { $plain = $plain.Substring(0, $cols) }
                                $l = "`e[1;30;46m" + $plain.PadRight($cols) + "`e[0m"
                                $sizedHead = $true
                            } else {
                                $l = "`e[1;96m$label`e[0;97m$arrow`e[0m" + $graph + $rendered
                            }
                        }
                        "arrow" {
                            $l = "`e[1;96m$label`e[0;97m$arrow`e[0m" + $graph + $rendered
                        }
                        "powerline" {
                            if ($isMain) {
                                $l = "`e[1;30;43m H+M  `e[0;33m`e[0m " + $graph + $rendered
                            } else {
                                $l = "`e[1;30;46m HEAD `e[0;36m`e[0m " + $graph + $rendered
                            }
                        }
                        "row-yellow" {
                            $plain = [regex]::Replace($label + $arrow + $graph + $rendered,
                                "`e\[[0-9;]*m", "")
                            if ($plain.Length -gt $cols) { $plain = $plain.Substring(0, $cols) }
                            $l = "`e[1;30;103m" + $plain.PadRight($cols) + "`e[0m"
                            $sizedHead = $true
                        }
                        "row-cyan" {
                            $l = "`e[48;5;23m`e[1;97m$label`e[22m$arrow" + $graph + $rendered
                            $l = $l.Replace("`e[0m", "`e[0;48;5;23m").Replace(
                                "`e[m", "`e[0;48;5;23m") + "`e[K`e[0m"
                            $sizedHead = $true
                        }
                        "arrow-hash" {
                            $rendered = $rendered.Replace($headShort,
                                "`e[1;97;44m$headShort`e[0m")
                            $l = "`e[1;96m$label`e[0;97m$arrow`e[0m" + $graph + $rendered
                        }
                        "hash" {
                            $rendered = $rendered.Replace($headShort,
                                "`e[1;97;44m$headShort`e[0m")
                            $l = $graph + $rendered
                        }
                    }
                } elseif ($mainOid -and $oid -eq $mainOid) {
                    if ($Theme -eq "hash") {
                        $l = $graph + $rendered
                    } elseif ($Theme -eq "powerline") {
                        $l = "`e[1;30;42m MAIN `e[0;32m`e[0m " + $graph + $rendered
                    } elseif ($Theme -eq "adaptive-diamond") {
                        $l = "`e[1;32mMAIN`e[0;97m -> `e[0m" + $mainGraph + $rendered
                    } else {
                        $l = "`e[1;32mMAIN`e[0;97m -> `e[0m" + $graph + $rendered
                    }
                } else {
                    $l = if ($Theme -eq "hash") {
                        $graph + $rendered
                    } else {
                        "        " + $graph + $rendered
                    }
                }
            }
        } else {
            # Graph connector-only rows need the same gutter to preserve the
            # shape and alignment of merge lines.
            if ($Theme -ne "hash") { $l = "        " + $l }
        }
        # Naive truncation to terminal width (ANSI codes count toward the limit,
        # same as cut -c in the Linux version)
        if (-not $sizedHead -and $l.Length -gt $cols) {
            $l = $l.Substring(0, $cols)
        }
        [Console]::WriteLine($l)
    }
}

# ── Main loop ──────────────────────────────────────────────────────────────
$lastPwd = ""
$lastHeadOid = ""
$lastTheme = ""

while ($true) {
    $curPwd = $StartDir
    if (Test-Path $PwdFile) {
        $r = Get-Content $PwdFile -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
        if ($r) { $curPwd = $r.Trim() }
    }

    $needsRefresh = Test-Path $RefreshFile
    $curTheme = "adaptive-diamond"
    if (Test-Path $ThemeFile) {
        $savedTheme = Get-Content $ThemeFile -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
        if ($savedTheme) { $curTheme = $savedTheme.Trim() }
    }

    if ($curPwd -ne $lastPwd -or $needsRefresh -or $curTheme -ne $lastTheme) {
        if ($needsRefresh) {
            Remove-Item $RefreshFile -Force -ErrorAction SilentlyContinue
        }
        $currentHeadOid = Get-CurrentHeadOid -Dir $curPwd
        $pulse = "None"
        if ($curTheme -eq "adaptive-diamond") {
            if ($currentHeadOid -and $currentHeadOid -ne $lastHeadOid) {
                $pulse = "Strong"
                $pulseDelay = 200
            } else {
                $pulse = "Subtle"
                $pulseDelay = 80
            }
        } elseif ($curTheme -eq "pulse-arrow") {
            $pulse = "Strong"
            $pulseDelay = 200
        }
        if ($pulse -ne "None") {
            Draw-GitLog -Dir $curPwd -Theme $curTheme -Pulse $pulse
            Start-Sleep -Milliseconds $pulseDelay
        }
        Draw-GitLog -Dir $curPwd -Theme $curTheme
        $lastPwd = $curPwd
        $lastHeadOid = $currentHeadOid
        $lastTheme = $curTheme
    }

    Start-Sleep -Milliseconds 500
}
