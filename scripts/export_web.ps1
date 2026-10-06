# Exports the LD60 project to build/web/ using the "Web" preset in
# export_presets.cfg, then zips build/web/ into a deploy artifact for
# hosting upload (itch.io, Cloudflare Pages, levi.dev, etc).
#
# The Web preset ships with threads and GDExtension support disabled,
# so the build runs from any plain static host. No COOP/COEP headers
# or SharedArrayBuffer support are required.
#
# Prereqs:
#   - Godot 4.7.x on PATH (with the standard web export templates
#     installed).
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File scripts/export_web.ps1
#
# Options:
#   -Debug    Export the debug variant (default: release).
#   -NoZip    Skip the zip step; leave build/web/ as-is.

param(
    [switch]$Debug,
    [switch]$NoZip
)

$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path -Parent $PSScriptRoot
$ExportDir = Join-Path $RepoRoot "build\web"
$OutputHtml = Join-Path $ExportDir "index.html"

# Clean previous export so deleted files don't linger in the zip.
if (Test-Path $ExportDir) {
    Write-Host "Clearing $ExportDir..." -ForegroundColor Yellow
    Remove-Item -Recurse -Force $ExportDir
}
New-Item -ItemType Directory -Force -Path $ExportDir | Out-Null

Push-Location $RepoRoot
try {
    $exportFlag = if ($Debug) { "--export-debug" } else { "--export-release" }
    Write-Host "Running godot $exportFlag `"Web`" $OutputHtml" -ForegroundColor Cyan
    # Godot writes its progress to stderr. Under a redirected console
    # (CI, captured output) PowerShell converts native stderr lines to
    # error records, and ErrorActionPreference=Stop would kill the
    # script on the first one. Relax it for just this call and
    # stringify the stream.
    $prevErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    & godot --headless $exportFlag "Web" $OutputHtml 2>&1 |
        ForEach-Object { "$_" }
    $ErrorActionPreference = $prevErrorActionPreference
    # Godot's headless export sometimes exits with a non-zero or null
    # code even when it successfully wrote every file (internal
    # ObjectDB-leak warning bumps exit status). Treat the presence of
    # the output html as the source of truth.
} finally {
    Pop-Location
}

if (-not (Test-Path $OutputHtml)) {
    throw "Export failed: $OutputHtml missing. Check Godot output above."
}

Write-Host "Export complete: $ExportDir" -ForegroundColor Green
Get-ChildItem $ExportDir | Select-Object Name, Length | Format-Table

if ($NoZip) {
    exit 0
}

$ZipPath = Join-Path $RepoRoot "build\ld60-web.zip"
if (Test-Path $ZipPath) {
    Remove-Item -Force $ZipPath
}
Write-Host "Zipping $ExportDir -> $ZipPath..." -ForegroundColor Cyan
Compress-Archive -Path (Join-Path $ExportDir "*") -DestinationPath $ZipPath
$size = (Get-Item $ZipPath).Length / 1MB
Write-Host ("Deploy artifact: $ZipPath ({0:N1} MB)" -f $size) -ForegroundColor Green
Write-Host ""
Write-Host "Next: upload the zip to itch.io (no SharedArrayBuffer needed),"
Write-Host "      or deploy build/web/ to any static host."
