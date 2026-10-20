# Records the Loose Screw trailer clips with Godot's movie
# writer, then cuts them into build/trailer/loose-screw-trailer.mp4
# and three page GIFs in build/trailer/gifs/.
#
#   powershell -ExecutionPolicy Bypass -File trailer/record.ps1
#   powershell -ExecutionPolicy Bypass -File trailer/record.ps1 -SkipRecord
#
# -SkipRecord re-cuts from the clips already in build/trailer/clips/.
param(
    [switch]$SkipRecord
)

$ErrorActionPreference = "Stop"
$repo = Split-Path $PSScriptRoot -Parent
$clipsDir = Join-Path $repo "build/trailer/clips"
$gifsDir = Join-Path $repo "build/trailer/gifs"
New-Item -ItemType Directory $clipsDir -Force | Out-Null
New-Item -ItemType Directory $gifsDir -Force | Out-Null

$godot = $env:GODOT
if (-not $godot) { $godot = "godot" }

$ffmpeg = Join-Path $env:LOCALAPPDATA `
    "Microsoft\WinGet\Packages\Gyan.FFmpeg_Microsoft.Winget.Source_8wekyb3d8bbwe\ffmpeg-9.0.2-full_build\bin\ffmpeg.exe"
if (-not (Test-Path $ffmpeg)) { $ffmpeg = "ffmpeg" }

# Clip name -> frame budget at 30 fps (the take's length).
$clips = @(
    @{ Name = "exterior"; Frames = 90 },
    @{ Name = "atari_open"; Frames = 240 },
    @{ Name = "tv_whack"; Frames = 210 },
    @{ Name = "yank_fit"; Frames = 360 },
    @{ Name = "glue"; Frames = 210 },
    @{ Name = "blast"; Frames = 165 },
    @{ Name = "radio"; Frames = 180 },
    @{ Name = "receipt"; Frames = 240 }
)

if (-not $SkipRecord) {
    foreach ($clip in $clips) {
        $movie = Join-Path $clipsDir "$($clip.Name).avi"
        Write-Host "Recording $($clip.Name) ($($clip.Frames) frames)..."
        & $godot --path $repo res://trailer/trailer.tscn `
            --write-movie $movie --fixed-fps 30 `
            --quit-after $clip.Frames --resolution 1280x720 `
            -- --clip=$($clip.Name) | Out-Null
        if (-not (Test-Path $movie)) {
            throw "Clip not recorded: $movie"
        }
    }
}

# --- Cut the trailer -------------------------------------------------

$font = "assets/fonts/special_elite/SpecialElite-Regular.ttf"
$inputs = @()
foreach ($clip in $clips) {
    $inputs += @("-i", (Join-Path $clipsDir "$($clip.Name).avi"))
}
$inputs += @(
    "-f", "lavfi", "-i",
    "color=c=0x191009:s=1280x720:r=30:d=3.5",
    "-f", "lavfi", "-i", "anullsrc=r=48000:cl=stereo"
)

$segmentCount = $clips.Count + 1
$endCardIndex = $clips.Count
$filter = ""
for ($i = 0; $i -lt $clips.Count; $i++) {
    $filter += "[$i`:v]setsar=1[v$i];[$i`:a]asetpts=N/SR/TB[a$i];"
}
$filter += "[$endCardIndex`:v]drawtext=fontfile='$font':text='Loose Screw':fontcolor=0xf3e2c2:fontsize=96:x=(w-text_w)/2:y=250,"
$filter += "drawtext=fontfile='$font':text='Every gadget deserves a second chance.':fontcolor=0xc9a06a:fontsize=34:x=(w-text_w)/2:y=380,"
$filter += "drawtext=fontfile='$font':text='levilindsey.itch.io/loose-screw':fontcolor=0xf3e2c2:fontsize=40:x=(w-text_w)/2:y=470,setsar=1[v$endCardIndex];"
$filter += "[$($endCardIndex + 1)`:a]atrim=0:3.5,asetpts=N/SR/TB[a$endCardIndex];"

$concatInputs = ""
for ($i = 0; $i -lt $segmentCount; $i++) {
    $concatInputs += "[v$i][a$i]"
}
$framesTotal = 0
foreach ($c in $clips) { $framesTotal += $c.Frames }
$totalSec = ($framesTotal / 30.0) + 3.5
$fadeStart = $totalSec - 1.5
$filter += "${concatInputs}concat=n=${segmentCount}:v=1:a=1[catv][cata];"
$filter += "[catv]fade=t=in:st=0:d=0.4,fade=t=out:st=${fadeStart}:d=1.0[vout];"
$filter += "[cata]afade=t=in:st=0:d=0.4,afade=t=out:st=${fadeStart}:d=1.0[aout]"

$trailer = Join-Path $repo "build/trailer/loose-screw-trailer.mp4"
Write-Host "Cutting $trailer ..."
& $ffmpeg -y -v error @inputs `
    -filter_complex $filter -map "[vout]" -map "[aout]" `
    -c:v libx264 -pix_fmt yuv420p -crf 19 -preset medium `
    -c:a aac -b:a 160k -movflags +faststart $trailer
if ($LASTEXITCODE -ne 0) { throw "ffmpeg trailer cut failed" }

# --- GIFs ------------------------------------------------------------
# Name -> (clip, start seconds). 5.5 s each at 15 fps, 640 wide.
$gifs = @(
    @{ Name = "glue-repair"; Clip = "glue"; Start = 1.0 },
    @{ Name = "shrink-ray-blast"; Clip = "blast"; Start = 0.5 },
    @{ Name = "yank-and-fit"; Clip = "yank_fit"; Start = 4.0 }
)
foreach ($gif in $gifs) {
    $source = Join-Path $clipsDir "$($gif.Clip).avi"
    $out = Join-Path $gifsDir "$($gif.Name).gif"
    $palette = Join-Path $gifsDir "$($gif.Name)-palette.png"
    Write-Host "Making $out ..."
    & $ffmpeg -y -v error -ss $gif.Start -t 5.5 -i $source `
        -vf "fps=15,scale=640:-1:flags=lanczos,palettegen=stats_mode=diff" `
        $palette
    if ($LASTEXITCODE -ne 0) { throw "palettegen failed for $out" }
    & $ffmpeg -y -v error -ss $gif.Start -t 5.5 -i $source -i $palette `
        -lavfi "fps=15,scale=640:-1:flags=lanczos[x];[x][1:v]paletteuse=dither=bayer:bayer_scale=4" `
        $out
    if ($LASTEXITCODE -ne 0) { throw "paletteuse failed for $out" }
    Remove-Item $palette
}

Write-Host "Done: $trailer"
Write-Host "GIFs in $gifsDir (upload via itch Edit game -> Screenshots;"
Write-Host "Butler cannot manage page screenshots)."
