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

function Invoke-StateGit {
    param(
        [string]$Dir,
        [string[]]$Arguments
    )
    if (git -C $Dir rev-parse --is-inside-work-tree 2>$null) {
        return & git -C $Dir @Arguments
    }
    if (Get-Command yadm -ErrorAction SilentlyContinue) {
        $homePath = [System.IO.Path]::GetFullPath($HOME).TrimEnd(
            [System.IO.Path]::DirectorySeparatorChar,
            [System.IO.Path]::AltDirectorySeparatorChar
        )
        $dirPath = [System.IO.Path]::GetFullPath($Dir)
        if (($dirPath -eq $homePath -or $dirPath.StartsWith(
                    $homePath + [System.IO.Path]::DirectorySeparatorChar,
                    [System.StringComparison]::OrdinalIgnoreCase)) -and
                (yadm rev-parse --is-inside-work-tree 2>$null)) {
            return & yadm @Arguments
        }
    }
    return $null
}

function Get-CurrentPrimaryOid {
    param([string]$Dir)

    $configured = Invoke-StateGit -Dir $Dir -Arguments @(
        "config", "--get", "surf.primaryBranch") 2>$null
    if ($configured) {
        foreach ($candidate in @("refs/heads/$configured",
                "refs/remotes/origin/$configured", $configured)) {
            $oid = Invoke-StateGit -Dir $Dir -Arguments @(
                "rev-parse", "--verify", $candidate) 2>$null
            if ($oid) { return $oid }
        }
    }

    $primaryRef = Invoke-StateGit -Dir $Dir -Arguments @(
        "symbolic-ref", "--quiet", "refs/remotes/origin/HEAD") 2>$null
    if ($primaryRef) {
        $name = $primaryRef -replace '^refs/remotes/origin/', ''
        $oid = Invoke-StateGit -Dir $Dir -Arguments @(
            "rev-parse", "--verify", "refs/heads/$name") 2>$null
        if (-not $oid) {
            $oid = Invoke-StateGit -Dir $Dir -Arguments @(
                "rev-parse", "--verify", $primaryRef) 2>$null
        }
        if ($oid) { return $oid }
    }

    foreach ($candidate in @("refs/heads/main", "refs/heads/master",
            "refs/remotes/origin/main", "refs/remotes/origin/master")) {
        $oid = Invoke-StateGit -Dir $Dir -Arguments @(
            "rev-parse", "--verify", $candidate) 2>$null
        if ($oid) { return $oid }
    }
    return $null
}

function Get-RepoSignature {
    param([string]$Dir)

    $head = Invoke-StateGit -Dir $Dir -Arguments @("rev-parse", "HEAD") 2>$null
    if (-not $head) { return "not-repo:$Dir" }
    $refs = Invoke-StateGit -Dir $Dir -Arguments @("for-each-ref",
        "--format=%(refname):%(objectname)", "refs/heads", "refs/remotes", "refs/tags") 2>$null
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($head + "`n" + ($refs -join "`n"))
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        return [Convert]::ToHexString($sha.ComputeHash($bytes))
    } finally {
        $sha.Dispose()
    }
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

    $decorationArgs = if ($Theme -eq "wide") {
        @("--decorate-refs=refs/remotes", "--decorate-refs=refs/tags")
    } else { @() }
    if ($useYadm) {
        # yadm covers $HOME recursively. A regular nested repository still wins.
        $headOid = yadm rev-parse HEAD 2>$null
        $headShort = yadm rev-parse --short HEAD 2>$null
        $lines = yadm log '--pretty=format:%H%x1f%C(yellow)%h%C(reset) %C(green)%>|(25)%cr%C(reset) %s %C(bold blue)<%cl>%C(reset) %C(auto)%D%C(reset)' --graph --all --topo-order -n $rows --color=always @decorationArgs 2>$null
    } else {
        $headOid = git -C $Dir rev-parse HEAD 2>$null
        $headShort = git -C $Dir rev-parse --short HEAD 2>$null
        $lines = git -C $Dir log '--pretty=format:%H%x1f%C(yellow)%h%C(reset) %C(green)%>|(25)%cr%C(reset) %s %C(bold blue)<%cl>%C(reset) %C(auto)%D%C(reset)' --graph --all --topo-order -n $rows --color=always @decorationArgs 2>$null
    }
    if (-not $lines) {
        Write-Host "(no commits)" -ForegroundColor DarkGray
        return
    }
    # Git's -n limits commits, but merge connectors can add physical rows.
    # Cap those rows before sizing the visible-branch gutter.
    $lines = @($lines | Select-Object -First $rows)
    $headMarker = $headOid + [char]0x1f
    if (-not ($lines | Where-Object { $_.Contains($headMarker) })) {
        if ($useYadm) {
            $lines = yadm log '--pretty=format:%H%x1f%C(yellow)%h%C(reset) %C(green)%>|(25)%cr%C(reset) %s %C(bold blue)<%cl>%C(reset) %C(auto)%D%C(reset)' --graph --all --date-order -n $rows --color=always @decorationArgs 2>$null
        } else {
            $lines = git -C $Dir log '--pretty=format:%H%x1f%C(yellow)%h%C(reset) %C(green)%>|(25)%cr%C(reset) %s %C(bold blue)<%cl>%C(reset) %C(auto)%D%C(reset)' --graph --all --date-order -n $rows --color=always @decorationArgs 2>$null
        }
        $lines = @($lines | Select-Object -First $rows)
    }

    function Invoke-RepoGit {
        param([string[]]$Arguments)
        if ($useYadm) { & yadm @Arguments } else { & git -C $Dir @Arguments }
    }

    $wideBranches = @{}
    if ($Theme -eq "wide") {
        $localRefs = Invoke-RepoGit @("for-each-ref", "--format=%(objectname) %(refname:short)",
            "refs/heads") 2>$null
        foreach ($refLine in $localRefs) {
            $spaceAt = $refLine.IndexOf(' ')
            if ($spaceAt -lt 1) { continue }
            $refOid = $refLine.Substring(0, $spaceAt)
            $refName = $refLine.Substring($spaceAt + 1)
            $isVisible = $false
            foreach ($visibleLine in $lines) {
                if ($visibleLine.Contains($refOid + [char]0x1f)) {
                    $isVisible = $true
                    break
                }
            }
            if ($isVisible) {
                $wideBranches[$refOid] = @($wideBranches[$refOid]) + $refName
            }
        }
    }

    $primaryOid = $null
    $primaryName = $null
    $configuredPrimary = Invoke-RepoGit @("config", "--get", "surf.primaryBranch") 2>$null
    if ($configuredPrimary) {
        foreach ($candidate in @("refs/heads/$configuredPrimary",
                "refs/remotes/origin/$configuredPrimary", $configuredPrimary)) {
            $resolved = Invoke-RepoGit @("rev-parse", "--verify", $candidate) 2>$null
            if ($resolved) {
                $primaryOid = $resolved
                $primaryName = $configuredPrimary -replace '^refs/heads/', '' `
                    -replace '^refs/remotes/origin/', ''
                break
            }
        }
    }
    if (-not $primaryOid) {
        $primaryRef = Invoke-RepoGit @("symbolic-ref", "--quiet",
            "refs/remotes/origin/HEAD") 2>$null
        if ($primaryRef) {
            $primaryName = $primaryRef -replace '^refs/remotes/origin/', ''
            # Use origin/HEAD to discover the branch name, then prefer the
            # local branch position when it is ahead of its tracking ref.
            $primaryOid = Invoke-RepoGit @("rev-parse", "--verify",
                "refs/heads/$primaryName") 2>$null
            if (-not $primaryOid) {
                $primaryOid = Invoke-RepoGit @("rev-parse", "--verify", $primaryRef) 2>$null
            }
            if (-not $primaryOid) { $primaryName = $null }
        }
    }
    if (-not $primaryOid) {
        foreach ($candidate in @("refs/heads/main", "refs/heads/master",
                "refs/remotes/origin/main", "refs/remotes/origin/master")) {
            $resolved = Invoke-RepoGit @("rev-parse", "--verify", $candidate) 2>$null
            if ($resolved) {
                $primaryOid = $resolved
                $primaryName = Split-Path $candidate -Leaf
                break
            }
        }
    }

    $gutterWidth = 8
    if ($primaryName) {
        $gutterWidth = [Math]::Max($gutterWidth, $primaryName.Length + 4)
    }
    if ($Theme -eq "wide") {
        $gutterWidth = 1
        foreach ($entry in $wideBranches.GetEnumerator()) {
            $wideWidth = if ($entry.Key -eq $headOid) { 8 } else { 0 }
            foreach ($branchName in $entry.Value) {
                $wideWidth += $branchName.Length + 4
            }
            $gutterWidth = [Math]::Max($gutterWidth, $wideWidth + 1)
        }
    }
    if ($primaryOid -and $headOid -eq $primaryOid) {
        $gutterWidth = if ($Theme -eq "powerline") {
            $primaryName.Length + 11
        } elseif ($Theme -eq "wide") {
            $gutterWidth
        } else {
            $primaryName.Length + 9
        }
    }
    if ($Theme -eq "hash") { $gutterWidth = 0 }
    $gutter = " " * $gutterWidth

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
                $primaryGraph = $graph
                if ($starAt -ge 0) {
                    $headGraph = $graph.Substring(0, $starAt) + "`e[1;96m◆`e[0m" +
                        $graph.Substring($starAt + 1)
                    $primaryGraph = $graph.Substring(0, $starAt) + "`e[1;32m◆`e[0m" +
                        $graph.Substring($starAt + 1)
                }
                $isHead = $oid -eq $headOid
                $isPrimary = $primaryOid -and $oid -eq $primaryOid
                if ($Theme -eq "wide" -and
                        ($isHead -or $wideBranches.ContainsKey($oid))) {
                    $widePrefix = ""
                    $wideVisible = 0
                    if ($isHead) {
                        $widePrefix = "`e[1;96mHEAD`e[0;97m -> "
                        $wideVisible += 8
                    }
                    foreach ($branchName in @($wideBranches[$oid])) {
                        $widePrefix += "`e[1;32m$branchName`e[0;97m -> "
                        $wideVisible += $branchName.Length + 4
                    }
                    $widePadding = " " * ($gutterWidth - $wideVisible)
                    $l = $widePadding + $widePrefix + "`e[0m" + $graph + $rendered
                } elseif ($isHead) {
                    $label = if ($isPrimary) { "HEAD+$primaryName" } else { "HEAD" }
                    $arrow = " -> "
                    $labelPadding = " " * ($gutterWidth - $label.Length - 4)
                    $styledLabel = "`e[1;96mHEAD`e[0m"
                    $pulsedLabel = "`e[1;30;46mHEAD`e[0m"
                    if ($isPrimary) {
                        $styledLabel += "`e[97m+`e[1;32m$primaryName`e[0m"
                        $pulsedLabel += "`e[97m+`e[1;32m$primaryName`e[0m"
                    }
                    switch ($Theme) {
                        "adaptive-diamond" {
                            if ($Pulse -eq "Strong") {
                                $plain = [regex]::Replace($label + $arrow + $labelPadding +
                                    $graph.Replace('*', '◆') + $rendered,
                                    "`e\[[0-9;]*m", "")
                                if ($plain.Length -gt $cols) { $plain = $plain.Substring(0, $cols) }
                                $l = "`e[1;30;46m" + $plain.PadRight($cols) + "`e[0m"
                                $sizedHead = $true
                            } elseif ($Pulse -eq "Subtle") {
                                $l = $pulsedLabel + "`e[97m$arrow$labelPadding`e[0m" +
                                    $headGraph + $rendered
                            } else {
                                $l = $styledLabel + "`e[97m$arrow$labelPadding`e[0m" +
                                    $headGraph + $rendered
                            }
                        }
                        "pulse-arrow" {
                            if ($Pulse -eq "Strong") {
                                $plain = [regex]::Replace($label + $arrow + $labelPadding +
                                    $graph + $rendered,
                                    "`e\[[0-9;]*m", "")
                                if ($plain.Length -gt $cols) { $plain = $plain.Substring(0, $cols) }
                                $l = "`e[1;30;46m" + $plain.PadRight($cols) + "`e[0m"
                                $sizedHead = $true
                            } else {
                                $l = $styledLabel + "`e[97m$arrow$labelPadding`e[0m" +
                                    $graph + $rendered
                            }
                        }
                        "arrow" {
                            $l = $styledLabel + "`e[97m$arrow$labelPadding`e[0m" +
                                $graph + $rendered
                        }
                        "powerline" {
                            if ($isPrimary) {
                                $l = "`e[1;30;46m HEAD `e[36;42m`e[30m $primaryName `e[0;32m`e[0m " +
                                    $graph + $rendered
                            } else {
                                $l = "`e[1;30;46m HEAD `e[0;36m`e[0m " +
                                    $labelPadding + $graph + $rendered
                            }
                        }
                        "row-yellow" {
                            $plain = [regex]::Replace($label + $arrow + $labelPadding +
                                $graph + $rendered,
                                "`e\[[0-9;]*m", "")
                            if ($plain.Length -gt $cols) { $plain = $plain.Substring(0, $cols) }
                            $l = "`e[1;30;103m" + $plain.PadRight($cols) + "`e[0m"
                            $sizedHead = $true
                        }
                        "row-cyan" {
                            $l = "`e[48;5;23m" + $styledLabel +
                                "`e[22;97m$arrow$labelPadding" + $graph + $rendered
                            $l = $l.Replace("`e[0m", "`e[0;48;5;23m").Replace(
                                "`e[m", "`e[0;48;5;23m") + "`e[K`e[0m"
                            $sizedHead = $true
                        }
                        "arrow-hash" {
                            $rendered = $rendered.Replace($headShort,
                                "`e[1;97;44m$headShort`e[0m")
                            $l = $styledLabel + "`e[97m$arrow$labelPadding`e[0m" +
                                $graph + $rendered
                        }
                        "hash" {
                            $rendered = $rendered.Replace($headShort,
                                "`e[1;97;44m$headShort`e[0m")
                            $l = $graph + $rendered
                        }
                    }
                } elseif ($primaryOid -and $oid -eq $primaryOid) {
                    $primaryPadding = " " * ($gutterWidth - $primaryName.Length - 4)
                    if ($Theme -eq "hash" -or $Theme -eq "wide") {
                        $l = $graph + $rendered
                    } elseif ($Theme -eq "powerline") {
                        $l = "`e[1;30;42m $primaryName `e[0;32m`e[0m " +
                            $primaryPadding + $graph + $rendered
                    } elseif ($Theme -eq "adaptive-diamond") {
                        $l = "`e[1;32m$primaryName`e[0;97m -> `e[0m" + $primaryPadding +
                            $primaryGraph + $rendered
                    } else {
                        $l = "`e[1;32m$primaryName`e[0;97m -> `e[0m" + $primaryPadding +
                            $graph + $rendered
                    }
                } else {
                    $l = $gutter + $graph + $rendered
                }
            }
        } else {
            # Graph connector-only rows need the same gutter to preserve the
            # shape and alignment of merge lines.
            $l = $gutter + $l
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
$lastPrimaryOid = ""
$lastRepoSignature = ""
$lastTheme = ""

while ($true) {
    # Fall back to $lastPwd (not $StartDir) so a transient read failure while
    # pwd.txt is being written doesn't briefly flash a stale/previous repo.
    # First iteration: $lastPwd is "" so $StartDir is used as the seed.
    $curPwd = if ($lastPwd) { $lastPwd } else { $StartDir }
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
        $currentPrimaryOid = Get-CurrentPrimaryOid -Dir $curPwd
        $currentRepoSignature = Get-RepoSignature -Dir $curPwd
        $shouldDraw = $curPwd -ne $lastPwd -or $curTheme -ne $lastTheme -or
            $currentRepoSignature -ne $lastRepoSignature
        if ($curTheme -eq "pulse-arrow" -and $needsRefresh) { $shouldDraw = $true }

        $pulse = "None"
        if ($lastRepoSignature -and
                ($currentHeadOid -ne $lastHeadOid -or
                 $currentPrimaryOid -ne $lastPrimaryOid) -and
                $curTheme -in @("adaptive-diamond", "pulse-arrow")) {
            $pulse = "Strong"
            $pulseDelay = 200
        } elseif ($shouldDraw -and $curTheme -eq "pulse-arrow") {
            $pulse = "Strong"
            $pulseDelay = 200
        }
        if ($shouldDraw -and $pulse -ne "None") {
            Draw-GitLog -Dir $curPwd -Theme $curTheme -Pulse $pulse
            Start-Sleep -Milliseconds $pulseDelay
        }
        if ($shouldDraw) { Draw-GitLog -Dir $curPwd -Theme $curTheme }
        $lastPwd = $curPwd
        $lastHeadOid = $currentHeadOid
        $lastPrimaryOid = $currentPrimaryOid
        $lastRepoSignature = $currentRepoSignature
        $lastTheme = $curTheme
    }

    Start-Sleep -Milliseconds 500
}
