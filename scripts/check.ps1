# Checks that the project imports and boots without script errors.
# Run it after every change, before you commit or push.
#
#   powershell -ExecutionPolicy Bypass -File scripts/check.ps1
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
#   4. Reads the logs in build/check/. A "SCRIPT ERROR" or an "ERROR:" line
#      fails the check: each is printed with the "at:" line after it, which
#      names a file and line. For a parse error in a class_name script,
#      Godot names the file ("Could not parse global class") but not the
#      faulty line, so open that file.
#
# It judges by the logs, not by Godot's exit code, because Godot exits
# non-zero on some successful runs (ObjectDB-leak warnings).
#
# Coverage: it sees only what the import and the boot load (the autoloads,
# the main scene and what they reference). A script that nothing loads yet
# is not parsed, so an error in it passes until something uses it.
#
# Finding Godot, in order: -Godot <exe>, then $env:GODOT, then "godot" on
# PATH. To set it for this PowerShell window:
#   $env:GODOT = "C:\path\to\Godot_v4.7.2-stable_win64_console.exe"
#
# Options:
#   -Godot <exe>   Use this Godot executable.
#   -SkipImport    Skip the import step.
#   -Frames <n>    Frames to boot for (default 1200).
#
# Exit codes: 0 = OK, 1 = the check failed, 2 = Godot was not found, could
# not be started, or the options are wrong.
#
# A Godot run that hangs is stopped after a timeout (import 300 s, boot
# 120 s). Only the process this script started is stopped, never Godot by
# name, because the Godot editor is usually open.

param(
    [string]$Godot = "",
    [switch]$SkipImport,
    [int]$Frames = 1200
)

$RepoRoot = (Split-Path -Parent $PSScriptRoot).TrimEnd('\')
$CheckDirectory = Join-Path $RepoRoot "build\check"
$ImportTimeoutSeconds = 300
$BootTimeoutSeconds = 120
$WantedVersion = "4.7"

# Log lines that fail the check. Case-sensitive. This covers Godot's
# "ERROR:", "SCRIPT ERROR:", "SHADER ERROR:" and "USER ERROR:" lines.
$ErrorPattern = "ERROR:"
$WarningPattern = "WARNING:"

# Error lines that are known to be harmless. Keep this list short and
# narrow, with a reason for each entry. A line that matches one of these
# is not counted as an error.
$AllowedErrorPatterns = @()

# How many failing lines to print before summarizing the rest.
$MaxPrintedErrors = 15


function Write-Check([string]$Text) {
    Write-Host "check: $Text"
}


function Write-Plain([string]$Text) {
    # Godot logs can hold characters a console may not show. Keep ASCII.
    Write-Host ($Text -replace '[^\x20-\x7E\t]', '?')
}


function Exit-Setup([string]$Text) {
    Write-Check "$Text"
    exit 2
}


function Format-Argument([string]$Text) {
    # Windows PowerShell 5.1 joins Start-Process arguments with spaces and
    # adds no quotes, so quote anything that holds a space.
    if ($Text -match '[\s"]') {
        return '"' + ($Text -replace '"', '\"') + '"'
    }
    return $Text
}


function Stop-ProcessTree([int]$ProcessId) {
    # Ends this one PID and the processes it started. Godot's console
    # launcher (Godot_*_console.exe) starts the real Godot as a child. This
    # is never by name.
    try {
        & taskkill.exe /PID $ProcessId /T /F 2>&1 | Out-Null
    } catch {
        # The process may already be gone.
    }
}


function Find-Godot([string]$Requested) {
    # Returns the path to the Godot executable, or exits with code 2.
    # Trim spaces and quotes: people paste "C:\path\Godot.exe" with quotes.
    $candidate = "$Requested".Trim().Trim('"')
    $origin = "-Godot"
    if (-not $candidate) {
        $candidate = "$env:GODOT".Trim().Trim('"')
        $origin = "`$env:GODOT"
    }
    if ($candidate) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
        $command = Get-Command $candidate -CommandType Application `
            -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($command) {
            return $command.Source
        }
        Exit-Setup "$origin is '$candidate', but there is no such file."
    }

    $command = Get-Command godot -CommandType Application `
        -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($command) {
        return $command.Source
    }

    Write-Check "Godot was not found (no -Godot, no `$env:GODOT, and no 'godot' on PATH)."
    Write-Check "Tell check.ps1 where Godot 4.7 is, in one of these ways:"
    Write-Host '  for this run:        -Godot "C:\path\to\Godot_v4.7.2-stable_win64_console.exe"'
    Write-Host '  for this window:     $env:GODOT = "C:\path\to\Godot_v4.7.2-stable_win64_console.exe"'
    Write-Host '  for every window:    setx GODOT "C:\path\to\Godot_v4.7.2-stable_win64_console.exe"'
    exit 2
}


function Invoke-Godot {
    # Runs Godot, waits up to TimeoutSeconds, and returns what happened.
    # Output goes to build/check/<Name>.stdout.txt and <Name>.stderr.txt.
    param(
        [string]$Executable,
        [string[]]$Arguments,
        [string]$Name,
        [int]$TimeoutSeconds
    )

    $stdoutPath = Join-Path $CheckDirectory "$Name.stdout.txt"
    $stderrPath = Join-Path $CheckDirectory "$Name.stderr.txt"
    $argumentLine = ($Arguments | ForEach-Object { Format-Argument $_ }) -join ' '

    $result = New-Object psobject -Property @{
        StartError = ""
        TimedOut = $false
        ExitCode = $null
        Seconds = 0.0
        ProcessId = 0
        StdoutPath = $stdoutPath
        StderrPath = $stderrPath
    }

    $stopwatch = [Diagnostics.Stopwatch]::StartNew()
    try {
        $process = Start-Process -FilePath $Executable `
            -ArgumentList $argumentLine `
            -WorkingDirectory $RepoRoot `
            -PassThru -NoNewWindow `
            -RedirectStandardOutput $stdoutPath `
            -RedirectStandardError $stderrPath `
            -ErrorAction Stop
    } catch {
        $result.StartError = $_.Exception.Message
        return $result
    }

    # Reading Handle keeps ExitCode readable after the process exits
    # (a Windows PowerShell quirk).
    $null = $process.Handle
    $result.ProcessId = $process.Id
    if ($process.WaitForExit($TimeoutSeconds * 1000)) {
        $process.WaitForExit()
        $result.ExitCode = $process.ExitCode
    } else {
        $result.TimedOut = $true
        Stop-ProcessTree $process.Id
        $null = $process.WaitForExit(10000)
    }
    $result.Seconds = [math]::Round($stopwatch.Elapsed.TotalSeconds, 1)
    return $result
}


function Read-Lines([string]$Path) {
    # The lines of a log, or an empty array if it is missing or locked.
    try {
        if (Test-Path -LiteralPath $Path -PathType Leaf) {
            return [string[]][IO.File]::ReadAllLines($Path)
        }
    } catch {
        # Fall through.
    }
    return [string[]]@()
}


function Test-Allowed([string]$Line) {
    foreach ($pattern in $AllowedErrorPatterns) {
        if ($Line -cmatch $pattern) {
            return $true
        }
    }
    return $false
}


function Get-ErrorIndexes([string[]]$Lines) {
    $found = @()
    for ($i = 0; $i -lt $Lines.Count; $i++) {
        if (($Lines[$i] -cmatch $ErrorPattern) -and -not (Test-Allowed $Lines[$i])) {
            $found += $i
        }
    }
    return $found
}


function Show-Errors([string]$Label, [string[]]$Lines, $Indexes) {
    Write-Check "$($Indexes.Count) error line(s) in the $Label log:"
    $printed = 0
    foreach ($index in $Indexes) {
        if ($printed -ge $MaxPrintedErrors) {
            break
        }
        Write-Plain $Lines[$index]
        # The line after an error names the file and line.
        if ($index + 1 -lt $Lines.Count -and $Lines[$index + 1] -cnotmatch $ErrorPattern) {
            Write-Plain $Lines[$index + 1]
        }
        $printed++
    }
    if ($Indexes.Count -gt $printed) {
        Write-Check "... and $($Indexes.Count - $printed) more."
    }
}


function Fail([string]$Text, [string]$LogPath) {
    Write-Check "FAIL: $Text"
    if ($LogPath) {
        Write-Check "The full log is $LogPath"
    }
    exit 1
}


function Remove-IfPresent([string]$Path) {
    if (Test-Path -LiteralPath $Path) {
        Remove-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    }
}


# Check the options.
if ($Frames -lt 1) {
    Exit-Setup "-Frames must be at least 1 (Godot treats 0 as 'never quit')."
}

$GodotPath = Find-Godot $Godot

# Start from clean logs so an old log can never pass for this run.
New-Item -ItemType Directory -Force -Path $CheckDirectory | Out-Null
foreach ($name in @("version", "import", "boot")) {
    Remove-IfPresent (Join-Path $CheckDirectory "$name.stdout.txt")
    Remove-IfPresent (Join-Path $CheckDirectory "$name.stderr.txt")
    Remove-IfPresent (Join-Path $CheckDirectory "$name.log")
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
    $importLog = Join-Path $CheckDirectory "import.log"
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
$bootLog = Join-Path $CheckDirectory "boot.log"
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

$warningCount = 0
foreach ($line in $bootLines) {
    if ($line -cmatch $WarningPattern) {
        $warningCount++
    }
}
Write-Check "$warningCount warning(s) in the boot log"
Write-Check "OK"
exit 0
