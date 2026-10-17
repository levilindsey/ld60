# Helpers shared by scripts/check.ps1 and tests/run.ps1. Dot-source this
# file; do not run it. The caller sets these first:
#
#   $RepoRoot      the repo root, without a trailing backslash.
#   $LogDirectory  where Godot's logs and output go (build\check, say).
#   $LogPrefix     the word that starts each status line ("check").
#
# The functions read those three variables and the settings below from the
# caller's scope, and Fail and Exit-Setup exit the calling script. Windows
# PowerShell 5.1 syntax only: no "??", no ternaries and no "&&".

# Log lines that fail a run. Case-sensitive. This covers Godot's "ERROR:",
# "SCRIPT ERROR:", "SHADER ERROR:" and "USER ERROR:" lines.
$ErrorPattern = "ERROR:"
$WarningPattern = "WARNING:"

# Error lines that are known to be harmless. Keep this list short and
# narrow, with a reason for each entry. A line that matches one of these
# is not counted as an error.
$AllowedErrorPatterns = @()

# How many failing lines to print before summarizing the rest.
$MaxPrintedErrors = 15


function Write-Check([string]$Text) {
    Write-Host "${LogPrefix}: $Text"
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
    Write-Check "Tell this script where Godot 4.7 is, in one of these ways:"
    Write-Host '  for this run:        -Godot "C:\path\to\Godot_v4.7.2-stable_win64_console.exe"'
    Write-Host '  for this window:     $env:GODOT = "C:\path\to\Godot_v4.7.2-stable_win64_console.exe"'
    Write-Host '  for every window:    setx GODOT "C:\path\to\Godot_v4.7.2-stable_win64_console.exe"'
    exit 2
}


function Invoke-Godot {
    # Runs Godot, waits up to TimeoutSeconds, and returns what happened.
    # Output goes to <Name>.stdout.txt and <Name>.stderr.txt in $LogDirectory.
    param(
        [string]$Executable,
        [string[]]$Arguments,
        [string]$Name,
        [int]$TimeoutSeconds
    )

    $stdoutPath = Join-Path $LogDirectory "$Name.stdout.txt"
    $stderrPath = Join-Path $LogDirectory "$Name.stderr.txt"
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
