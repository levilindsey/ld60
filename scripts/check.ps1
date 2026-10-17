# Checks that the project imports, boots and loads without script errors.
# Run it after every change, before you commit or push.
#
#   powershell -ExecutionPolicy Bypass -File scripts/check.ps1
#   powershell -ExecutionPolicy Bypass -File scripts/check.ps1 -Tests
#
# The same line works from Git Bash (Claude Code's Bash tool on Windows).
# It runs under Windows PowerShell 5.1, so it keeps to that syntax: no
# "??", no ternaries and no "&&".
#
# What it does:
#   1. Finds Godot (see below) and prints its version. Anything but
#      4.7.x is a warning, not a failure.
#   2. Imports the project (headless). That is needed after a clone, after
#      a pull that adds a class_name, and after new assets. Skip it with
#      -SkipImport when none of those happened.
#   3. Boots the project (headless) for -Frames frames.
#   4. Sweeps: runs tests/sweep/sweep.tscn (headless), which loads every
#      .gd, .tscn and .tres under src/ and reports each one that fails.
#   5. With -Tests, runs the probes in tests/ (tests/run.ps1, about 90 s).
#   6. Reads the logs in build/check/. A "SCRIPT ERROR" or an "ERROR:" line
#      fails the check: each is printed with the "at:" line after it, which
#      names a file and line. For a parse error in a class_name script,
#      Godot names the file ("Could not parse global class") but not the
#      faulty line, so open that file.
#
# It judges by the logs, not by Godot's exit code, because Godot exits
# non-zero on some successful runs (ObjectDB-leak warnings).
#
# Coverage: the import and the boot parse only what the main scene reaches
# (the autoloads and what they reference), so the sweep loads the rest of
# src/. A script outside src/ is not swept. A planted parse error in a new
# script that nothing loads still fails the check, in the sweep.
#
# Finding Godot, in order: -Godot <exe>, then $env:GODOT, then "godot" on
# PATH. To set it for this PowerShell window:
#   $env:GODOT = "C:\path\to\Godot_v4.7.2-stable_win64_console.exe"
#
# Options:
#   -Godot <exe>   Use this Godot executable.
#   -SkipImport    Skip the import step.
#   -Frames <n>    Frames to boot for (default 1200).
#   -Tests         Also run the probes in tests/ after the sweep.
#
# Exit codes: 0 = OK, 1 = the check failed, 2 = Godot was not found, could
# not be started, or the options are wrong.
#
# A Godot run that hangs is stopped after a timeout (import 300 s, boot
# 120 s, sweep 60 s). Only the process this script started is stopped,
# never Godot by name, because the Godot editor is usually open.

param(
    [string]$Godot = "",
    [switch]$SkipImport,
    [int]$Frames = 1200,
    [switch]$Tests
)

$RepoRoot = (Split-Path -Parent $PSScriptRoot).TrimEnd('\')
$LogDirectory = Join-Path $RepoRoot "build\check"
$LogPrefix = "check"
$ImportTimeoutSeconds = 300
$BootTimeoutSeconds = 120
$SweepTimeoutSeconds = 60
$WantedVersion = "4.7"

# Find-Godot, Invoke-Godot, the log readers, Fail and the error settings.
. (Join-Path $PSScriptRoot "godot_helpers.ps1")


# Check the options.
if ($Frames -lt 1) {
    Exit-Setup "-Frames must be at least 1 (Godot treats 0 as 'never quit')."
}

$GodotPath = Find-Godot $Godot

# Start from clean logs so an old log can never pass for this run.
New-Item -ItemType Directory -Force -Path $LogDirectory | Out-Null
foreach ($name in @("version", "import", "boot", "sweep")) {
    Remove-IfPresent (Join-Path $LogDirectory "$name.stdout.txt")
    Remove-IfPresent (Join-Path $LogDirectory "$name.stderr.txt")
    Remove-IfPresent (Join-Path $LogDirectory "$name.log")
}

# Godot version.
$versionRun = Invoke-Godot -Executable $GodotPath -Arguments @("--version") `
    -Name "version" -TimeoutSeconds 30
if ($versionRun.StartError) {
    Write-Check "Could not start $GodotPath"
    Write-Check $versionRun.StartError
    Write-Check "Point -Godot or `$env:GODOT at the real Godot .exe (not a shortcut or shim)."
    exit 2
}
$versionText = ""
foreach ($line in (Read-Lines $versionRun.StdoutPath)) {
    if ($line.Trim()) {
        $versionText = $line.Trim()
        break
    }
}
if (-not $versionText) {
    Write-Check "Godot printed no version, so it may not be Godot: $GodotPath"
    Write-Check "WARNING: could not read the version; expected $WantedVersion.x."
} elseif ($versionText -notmatch '^\d+\.\d+') {
    $shown = $versionText -replace '[^\x20-\x7E]', '?'
    Write-Check "WARNING: '$shown' does not look like a Godot version: $GodotPath"
} else {
    Write-Check "Godot $versionText ($GodotPath)"
    if (-not $versionText.StartsWith("$WantedVersion.")) {
        Write-Check "WARNING: this project targets Godot $WantedVersion.x, so results may differ."
    }
}

# Import.
if ($SkipImport) {
    Write-Check "import skipped (-SkipImport)"
} else {
    $importLog = Join-Path $LogDirectory "import.log"
    Write-Check "importing the project (up to $ImportTimeoutSeconds s)..."
    $import = Invoke-Godot -Executable $GodotPath -Name "import" `
        -TimeoutSeconds $ImportTimeoutSeconds `
        -Arguments @("--headless", "--path", $RepoRoot, "--import", "--log-file", $importLog)
    if ($import.StartError) {
        Write-Check "Could not start Godot: $($import.StartError)"
        exit 2
    }
    if ($import.TimedOut) {
        Fail "the import did not finish in $ImportTimeoutSeconds s (stopped PID $($import.ProcessId))." $importLog
    }
    Write-Check "import finished in $($import.Seconds) s"
    $importLines = @(Read-Lines $importLog)
    $importErrors = @(Get-ErrorIndexes $importLines)
    if ($importErrors.Count -gt 0) {
        Show-Errors "import" $importLines $importErrors
        Fail "the import logged errors." $importLog
    }
}

# Boot.
$bootLog = Join-Path $LogDirectory "boot.log"
Write-Check "booting for $Frames frames (up to $BootTimeoutSeconds s)..."
$boot = Invoke-Godot -Executable $GodotPath -Name "boot" `
    -TimeoutSeconds $BootTimeoutSeconds `
    -Arguments @("--headless", "--path", $RepoRoot, "--quit-after", "$Frames", "--log-file", $bootLog)
if ($boot.StartError) {
    Write-Check "Could not start Godot: $($boot.StartError)"
    exit 2
}
if ($boot.TimedOut) {
    Fail "the boot did not finish in $BootTimeoutSeconds s (stopped PID $($boot.ProcessId))." $bootLog
}
Write-Check "boot finished in $($boot.Seconds) s"

$bootLines = @(Read-Lines $bootLog)
if ($bootLines.Count -eq 0) {
    Fail "Godot wrote no boot log (exit code $($boot.ExitCode))." $bootLog
}
$bootErrors = @(Get-ErrorIndexes $bootLines)
if ($bootErrors.Count -gt 0) {
    Show-Errors "boot" $bootLines $bootErrors
    Fail "the boot logged errors." $bootLog
}

# Sweep: load every script and scene under src/. The import and the boot
# parse only what the main scene reaches, so an error in any other script
# shows up here. The scene prints one "SWEEP FAIL:" line per file that does
# not load, and a "SWEEP SUMMARY:" line.
$sweepLog = Join-Path $LogDirectory "sweep.log"
Write-Check "sweeping src/ (up to $SweepTimeoutSeconds s)..."
$sweep = Invoke-Godot -Executable $GodotPath -Name "sweep" `
    -TimeoutSeconds $SweepTimeoutSeconds `
    -Arguments @("--headless", "--path", $RepoRoot, "res://tests/sweep/sweep.tscn", "--log-file", $sweepLog)
if ($sweep.StartError) {
    Write-Check "Could not start Godot: $($sweep.StartError)"
    exit 2
}
if ($sweep.TimedOut) {
    Fail "the sweep did not finish in $SweepTimeoutSeconds s (stopped PID $($sweep.ProcessId))." $sweepLog
}

$sweepLines = @(Read-Lines $sweepLog)
if ($sweepLines.Count -eq 0) {
    Fail "Godot wrote no sweep log (exit code $($sweep.ExitCode))." $sweepLog
}
$sweepErrors = @(Get-ErrorIndexes $sweepLines)
$sweepFailures = @($sweepLines | Where-Object { $_ -cmatch '^SWEEP FAIL: ' })
if ($sweepErrors.Count -gt 0) {
    Show-Errors "sweep" $sweepLines $sweepErrors
}
foreach ($line in $sweepFailures) {
    Write-Plain $line
}
if ($sweepErrors.Count -gt 0 -or $sweepFailures.Count -gt 0) {
    Fail "the sweep found a script or scene that does not load." $sweepLog
}
$sweepSummary = @($sweepLines | Where-Object { $_ -cmatch '^SWEEP SUMMARY: \d+ loaded, 0 failed' })
if ($sweepSummary.Count -eq 0) {
    Fail "the sweep printed no summary, so it may not have finished (exit code $($sweep.ExitCode))." $sweepLog
}
Write-Check "sweep finished in $($sweep.Seconds) s ($($sweepSummary[0] -replace '^SWEEP SUMMARY: ', ''))"

# Probes, on request.
if ($Tests) {
    Write-Check "running the probes (tests/run.ps1)..."
    $global:LASTEXITCODE = 1
    & (Join-Path $RepoRoot "tests\run.ps1") -Godot $GodotPath
    $testsExit = $global:LASTEXITCODE
    if ($testsExit -eq 2) {
        exit 2
    }
    if ($testsExit -ne 0) {
        Fail "the probes failed (see above)." ""
    }
}

$warningCount = 0
foreach ($line in $bootLines) {
    if ($line -cmatch $WarningPattern) {
        $warningCount++
    }
}
Write-Check "$warningCount warning(s) in the boot log"
Write-Check "OK"
exit 0
