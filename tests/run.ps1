# Runs the probes in tests/ headless and prints one result line for each.
#
#   powershell -ExecutionPolicy Bypass -File tests/run.ps1
#   powershell -ExecutionPolicy Bypass -File tests/run.ps1 -Name screws
#
# scripts/check.ps1 -Tests checks the project first (import, boot, sweep)
# and then calls this script. Run this one on its own to rerun a probe, but
# the project must have been imported once (scripts/check.ps1 does that).
#
# A probe is a scene, tests/<folder>/probe.tscn, that boots the game and
# plays it with pushed input. It prints "PROBE SUMMARY: <n> passed, <m>
# failed". A run passes when the summary shows at least one check and 0
# failed, the log has no "SCRIPT ERROR" or "ERROR:" line, and the probe
# did not time out. It judges by the log, not by Godot's exit code, like
# check.ps1. Logs go to build/tests/<run>.log (git-ignored).
#
# The runs are in the table below. A new probe folder needs a row there.
#
# Options:
#   -Name <run>    Run just this one (a name from the table).
#   -Godot <exe>   Use this Godot executable. Without it: $env:GODOT, then
#                  "godot" on PATH, like check.ps1.
#   -Screenshots   Run windowed and save PNGs of the bench to
#                  build/tests/<folder>/. It needs -Name, opens a window on
#                  your screen for a few seconds and takes no real mouse
#                  input, but keep the mouse still anyway (LX44).
#
# Exit codes: 0 = every run passed, 1 = a run failed, 2 = Godot was not
# found or could not be started, or the options or the probes are wrong.
#
# A Godot run that hangs is stopped after its timeout. Only the process
# this script started is stopped, never Godot by name, because the Godot
# editor is usually open. It runs under Windows PowerShell 5.1.

param(
    [string]$Name = "",
    [string]$Godot = "",
    [switch]$Screenshots
)

$RepoRoot = (Split-Path -Parent $PSScriptRoot).TrimEnd('\')
$LogDirectory = Join-Path $RepoRoot "build\tests"
$LogPrefix = "tests"
. (Join-Path $RepoRoot "scripts\godot_helpers.ps1")

# Every run: its name, the folder in tests/ that holds the probe, the
# arguments the probe reads (after "--"), a timeout above the probe's own,
# and the extra Godot arguments for a windowed -Screenshots run.
$Runs = @(
    @{ Name = "full_loop"; Probe = "full_loop"; UserArguments = @(); TimeoutSeconds = 150; WindowedArguments = @("--debug-collisions") },
    @{ Name = "full_loop_booklet"; Probe = "full_loop"; UserArguments = @("--booklet"); TimeoutSeconds = 60; WindowedArguments = @("--debug-collisions") },
    @{ Name = "item_flow"; Probe = "item_flow"; UserArguments = @(); TimeoutSeconds = 90; WindowedArguments = @() },
    @{ Name = "screws"; Probe = "screws"; UserArguments = @(); TimeoutSeconds = 150; WindowedArguments = @() }
    @{ Name = "parts"; Probe = "parts"; UserArguments = @(); TimeoutSeconds = 90; WindowedArguments = @() }
    @{ Name = "tools"; Probe = "tools"; UserArguments = @(); TimeoutSeconds = 150; WindowedArguments = @() }
    @{ Name = "phillips"; Probe = "phillips"; UserArguments = @(); TimeoutSeconds = 180; WindowedArguments = @() }
    @{ Name = "glue"; Probe = "glue"; UserArguments = @(); TimeoutSeconds = 120; WindowedArguments = @() }
    @{ Name = "audio"; Probe = "audio"; UserArguments = @(); TimeoutSeconds = 90; WindowedArguments = @() }
    @{ Name = "decals"; Probe = "decals"; UserArguments = @(); TimeoutSeconds = 90; WindowedArguments = @() }
    @{ Name = "bench_drag"; Probe = "bench_drag"; UserArguments = @(); TimeoutSeconds = 150; WindowedArguments = @() }
    @{ Name = "bird"; Probe = "bird"; UserArguments = @(); TimeoutSeconds = 90; WindowedArguments = @() }
    @{ Name = "workable"; Probe = "workable"; UserArguments = @(); TimeoutSeconds = 150; WindowedArguments = @() }
    @{ Name = "radio"; Probe = "radio"; UserArguments = @(); TimeoutSeconds = 90; WindowedArguments = @() }
    @{ Name = "hints"; Probe = "hints"; UserArguments = @(); TimeoutSeconds = 90; WindowedArguments = @() }
    @{ Name = "screw_swap"; Probe = "screw_swap"; UserArguments = @(); TimeoutSeconds = 150; WindowedArguments = @() }
)


# Check the options and the probes.
$selected = @($Runs)
if ($Name) {
    $selected = @($Runs | Where-Object { $_.Name -eq $Name })
    if ($selected.Count -eq 0) {
        $names = ($Runs | ForEach-Object { $_.Name }) -join ", "
        Exit-Setup "There is no run named '$Name'. The runs are: $names."
    }
}
if ($Screenshots -and -not $Name) {
    Exit-Setup "-Screenshots opens a window, so name the run to take it from: -Name <run>."
}

$testsDirectory = Join-Path $RepoRoot "tests"
$registered = @($Runs | ForEach-Object { $_.Probe } | Select-Object -Unique)
foreach ($probe in $registered) {
    if (-not (Test-Path -LiteralPath (Join-Path $testsDirectory "$probe\probe.tscn") -PathType Leaf)) {
        Exit-Setup "tests/$probe/probe.tscn is in the run table of tests/run.ps1, but the file is missing."
    }
}
foreach ($directory in (Get-ChildItem -LiteralPath $testsDirectory -Directory)) {
    $hasProbe = Test-Path -LiteralPath (Join-Path $directory.FullName "probe.tscn") -PathType Leaf
    if ($hasProbe -and ($registered -notcontains $directory.Name)) {
        Exit-Setup "tests/$($directory.Name)/probe.tscn has no row in the run table of tests/run.ps1, so it would never run."
    }
}
if (-not (Test-Path -LiteralPath (Join-Path $RepoRoot ".godot\global_script_class_cache.cfg") -PathType Leaf)) {
    Exit-Setup "The project has not been imported yet. Run scripts/check.ps1 once first."
}

$GodotPath = Find-Godot $Godot
New-Item -ItemType Directory -Force -Path $LogDirectory | Out-Null

if ($Screenshots) {
    Write-Check "windowed run: a window opens for a few seconds. Keep the mouse still (LX44)."
}

$failedNames = @()
$totalSeconds = 0.0
foreach ($run in $selected) {
    $logPath = Join-Path $LogDirectory "$($run.Name).log"
    # Start from clean logs so an old log can never pass for this run.
    Remove-IfPresent $logPath
    Remove-IfPresent (Join-Path $LogDirectory "$($run.Name).stdout.txt")
    Remove-IfPresent (Join-Path $LogDirectory "$($run.Name).stderr.txt")

    $arguments = @()
    if (-not $Screenshots) {
        $arguments += "--headless"
    }
    $arguments += @("--path", $RepoRoot)
    if ($Screenshots) {
        $arguments += @($run.WindowedArguments)
    }
    $arguments += @("res://tests/$($run.Probe)/probe.tscn", "--log-file", $logPath)
    $userArguments = @($run.UserArguments)
    if ($Screenshots) {
        $userArguments += "--screenshots"
    }
    if ($userArguments.Count -gt 0) {
        $arguments += "--"
        $arguments += $userArguments
    }

    $result = Invoke-Godot -Executable $GodotPath -Name $run.Name `
        -TimeoutSeconds $run.TimeoutSeconds -Arguments $arguments
    if ($result.StartError) {
        Write-Check "Could not start Godot: $($result.StartError)"
        exit 2
    }
    $totalSeconds += $result.Seconds

    # Why the run failed, or an empty string if it passed.
    $reason = ""
    $lines = @(Read-Lines $logPath)
    $passed = 0
    $failed = 0
    $hasSummary = $false
    foreach ($line in $lines) {
        if ($line -cmatch '^PROBE SUMMARY: (\d+) passed, (\d+) failed') {
            $hasSummary = $true
            $passed = [int]$Matches[1]
            $failed = [int]$Matches[2]
        }
    }
    $errorIndexes = @(Get-ErrorIndexes $lines)
    $timeoutLines = @($lines | Where-Object { $_ -cmatch '^PROBE TIMEOUT' })

    if ($result.TimedOut) {
        $reason = "no result after $($run.TimeoutSeconds) s (stopped PID $($result.ProcessId))"
    } elseif ($lines.Count -eq 0) {
        $reason = "Godot wrote no log (exit code $($result.ExitCode))"
    } elseif ($errorIndexes.Count -gt 0) {
        $reason = "$($errorIndexes.Count) error line(s) in the log"
    } elseif ($timeoutLines.Count -gt 0) {
        $reason = "the probe timed out ($($timeoutLines[0]))"
    } elseif (-not $hasSummary) {
        $reason = "no PROBE SUMMARY line, so the probe may have crashed (exit code $($result.ExitCode))"
    } elseif ($failed -gt 0) {
        $reason = "$failed of $($passed + $failed) check(s) failed"
    } elseif ($passed -eq 0) {
        $reason = "no checks ran"
    }

    if (-not $reason) {
        Write-Check "PASS $($run.Name) ($passed checks, $($result.Seconds) s)"
    } else {
        Write-Check "FAIL $($run.Name): $reason ($($result.Seconds) s)"
        $failedNames += $run.Name
        if ($errorIndexes.Count -gt 0) {
            Show-Errors $run.Name $lines $errorIndexes
        }
        $shown = 0
        foreach ($line in $lines) {
            if ($line -cmatch '^PROBE FAILED: ') {
                if ($shown -lt $MaxPrintedErrors) {
                    Write-Plain $line
                }
                $shown++
            }
        }
        Write-Check "The full log is $logPath"
    }

    if ($Screenshots) {
        foreach ($line in $lines) {
            if ($line -cmatch '^PROBE (SHOT|REAL INPUT):') {
                Write-Plain $line
            }
        }
    }
}

$seconds = [math]::Round($totalSeconds, 1)
if ($failedNames.Count -gt 0) {
    Write-Check "FAIL: $($failedNames.Count) of $($selected.Count) run(s) failed: $($failedNames -join ', ')."
    exit 1
}
Write-Check "OK ($($selected.Count) run(s), $seconds s)"
exit 0
