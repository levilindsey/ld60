# Exports the LD60 web build and pushes it to itch.io with Butler:
#   levilindsey/repair-shop, channel "html5" (the playable-in-browser build).
#
# One-time setup (per machine):
#   1. Install Butler (https://itchio.itch.io/butler). On Levi's machines
#      it lives at %USERPROFILE%\Tools\butler\butler.exe; anywhere on the
#      PATH works too. This script finds either.
#   2. Log in once:  butler login
#      (Opens a browser; the token is stored in ~\.config\itch\butler_creds.)
#
# The itch page can stay Restricted while testing: Butler pushes work the
# same in Draft, Restricted and Public. Flip the page to Public in the
# itch dashboard when the game is ready for players.
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File scripts/deploy_itch.ps1
#
# Options:
#   -Version <x>  Version label shown on itch.io (default: config/version
#                 from project.godot).
#   -DryRun       Show what would be pushed, without uploading anything.
#   -SkipExport   Push the existing build\web\ as-is (no fresh export).

param(
    [string]$Version,
    [switch]$DryRun,
    [switch]$SkipExport
)

$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path -Parent $PSScriptRoot
$ExportDir = Join-Path $RepoRoot "build\web"
$IndexHtml = Join-Path $ExportDir "index.html"
$Target = "levilindsey/repair-shop:html5"

# Find Butler: PATH first, then the per-machine Tools folder.
$butler = $null
$onPath = Get-Command butler -ErrorAction SilentlyContinue
if ($onPath) {
    $butler = $onPath.Source
} else {
    $inTools = Join-Path $HOME "Tools\butler\butler.exe"
    if (Test-Path $inTools) {
        $butler = $inTools
    }
}
if (-not $butler) {
    throw "Butler not found. Install it from https://itchio.itch.io/butler (or put butler.exe in $HOME\Tools\butler\), then run 'butler login' once."
}
Write-Host "Using Butler: $butler" -ForegroundColor Cyan

# Default version label: config/version in project.godot.
if (-not $Version) {
    $match = Select-String -Path (Join-Path $RepoRoot "project.godot") `
        -Pattern 'config/version="([^"]+)"'
    if ($match) {
        $Version = $match.Matches[0].Groups[1].Value
    } else {
        $Version = "dev"
    }
}

# Fresh web export, unless asked to reuse the last one. Runs as a child
# process because export_web.ps1 ends with `exit`, which would stop this
# script too if it ran in-process.
if (-not $SkipExport) {
    Write-Host "Exporting fresh web build..." -ForegroundColor Cyan
    & powershell -ExecutionPolicy Bypass -File `
        (Join-Path $PSScriptRoot "export_web.ps1") -NoZip
    if ($LASTEXITCODE -ne 0) {
        throw "Web export failed (exit $LASTEXITCODE). See output above."
    }
}
if (-not (Test-Path $IndexHtml)) {
    throw "Nothing to push: $IndexHtml is missing. Run without -SkipExport to export first."
}

$pushArgs = @("push", $ExportDir, $Target, "--userversion", $Version)
if ($DryRun) {
    $pushArgs += "--dry-run"
}
Write-Host "Running: butler $($pushArgs -join ' ')" -ForegroundColor Cyan
& $butler @pushArgs
if ($LASTEXITCODE -ne 0) {
    throw "Butler push failed (exit $LASTEXITCODE). If it says you are not logged in, run 'butler login' once, then re-run this script."
}

if ($DryRun) {
    Write-Host "Dry run complete: nothing was uploaded." -ForegroundColor Green
} else {
    Write-Host "Pushed version $Version to https://levilindsey.itch.io/repair-shop" -ForegroundColor Green
    Write-Host "First push? In the itch dashboard (Edit game), check the embed"
    Write-Host "size fits the game (1280x720) and flip visibility to Public when ready."
}
