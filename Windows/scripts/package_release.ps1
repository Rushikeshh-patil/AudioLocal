[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Version,

    [Parameter()]
    [int]$BuildNumber = 0,

    [Parameter()]
    [ValidateSet("x64")]
    [string]$Architecture = "x64",

    [Parameter()]
    [string]$BundledRuntimeRoot = "",

    [Parameter()]
    [string]$BundledFfmpegPath = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.IO.Compression.FileSystem

function Get-MsiVersion {
    param([Parameter(Mandatory = $true)][string]$VersionText)

    $parts = [regex]::Matches($VersionText, '\d+') | ForEach-Object { [int]$_.Value }
    $major = if ($parts.Count -ge 1) { $parts[0] } else { 0 }
    $minor = if ($parts.Count -ge 2) { $parts[1] } else { 1 }
    $patch = if ($parts.Count -ge 3) { $parts[2] } else { 0 }
    return "{0}.{1}.{2}" -f $major, $minor, $patch
}

function Write-Sha256File {
    param([Parameter(Mandatory = $true)][string]$Path)

    $hash = Get-FileHash -Path $Path -Algorithm SHA256
    $content = "{0} *{1}" -f $hash.Hash.ToLowerInvariant(), [System.IO.Path]::GetFileName($Path)
    Set-Content -Path "$Path.sha256" -Value $content -Encoding ascii
}

function Get-RuntimeArchiveSources {
    param(
        [Parameter(Mandatory = $true)][string]$SourceRoot
    )

    $sources = @{}
    if (-not (Test-Path -LiteralPath $SourceRoot)) {
        return $sources
    }

    foreach ($folderName in @("KokoroCuda", "KokoroDirectML", "KokoroCpu")) {
        $source = Join-Path $SourceRoot $folderName
        if (-not (Test-Path -LiteralPath $source)) {
            continue
        }

        $sources[$folderName] = $source
    }

    if (-not $sources.ContainsKey("KokoroCpu") -and $sources.ContainsKey("KokoroDirectML")) {
        $sources["KokoroCpu"] = $sources["KokoroDirectML"]
    }

    return $sources
}

function Write-RuntimeArchive {
    param(
        [Parameter(Mandatory = $true)][string]$SourceDirectory,
        [Parameter(Mandatory = $true)][string]$DestinationArchivePath
    )

    if (Test-Path -LiteralPath $DestinationArchivePath) {
        Remove-Item -LiteralPath $DestinationArchivePath -Force
    }

    [System.IO.Compression.ZipFile]::CreateFromDirectory(
        $SourceDirectory,
        $DestinationArchivePath,
        [System.IO.Compression.CompressionLevel]::Optimal,
        $false)
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$windowsRoot = Join-Path $repoRoot "Windows"
$publishDir = Join-Path $windowsRoot "artifacts\publish\win-$Architecture"
$runtimeArchiveDir = Join-Path $publishDir "RuntimeArchives"
$distDir = Join-Path $repoRoot "dist"
$installerProject = Join-Path $windowsRoot "installer\AudioLocal.Windows.Installer.wixproj"
$generatedWxs = Join-Path $windowsRoot "installer\GeneratedFiles.wxs"
$artifactBaseName = "AudioLocal-Windows-$Architecture-$Version"
$zipPath = Join-Path $distDir "$artifactBaseName.zip"
$msiPath = Join-Path $distDir "$artifactBaseName.msi"
$msiVersion = Get-MsiVersion -VersionText $Version

if (Test-Path -LiteralPath $publishDir) {
    Remove-Item -LiteralPath $publishDir -Recurse -Force
}

if (Test-Path -LiteralPath $zipPath) {
    Remove-Item -LiteralPath $zipPath -Force
}

if (Test-Path -LiteralPath $msiPath) {
    Remove-Item -LiteralPath $msiPath -Force
}

New-Item -ItemType Directory -Force -Path $publishDir | Out-Null
New-Item -ItemType Directory -Force -Path $distDir | Out-Null

dotnet publish (Join-Path $windowsRoot "src\AudioLocal.Windows\AudioLocal.Windows.csproj") `
    -c Release `
    -r "win-$Architecture" `
    -o $publishDir `
    -p:UseSharedCompilation=false

New-Item -ItemType Directory -Force -Path $runtimeArchiveDir | Out-Null

$runtimeRoot = if ([string]::IsNullOrWhiteSpace($BundledRuntimeRoot)) { $env:AUDIOLOCAL_WINDOWS_RUNTIME_ROOT } else { $BundledRuntimeRoot }
if (-not [string]::IsNullOrWhiteSpace($runtimeRoot)) {
    $runtimeSources = Get-RuntimeArchiveSources -SourceRoot $runtimeRoot
    foreach ($runtimeName in $runtimeSources.Keys) {
        $archivePath = Join-Path $runtimeArchiveDir "$runtimeName.zip"
        Write-RuntimeArchive -SourceDirectory $runtimeSources[$runtimeName] -DestinationArchivePath $archivePath
    }
}

$ffmpegPath = if ([string]::IsNullOrWhiteSpace($BundledFfmpegPath)) { $env:AUDIOLOCAL_WINDOWS_FFMPEG_PATH } else { $BundledFfmpegPath }
if (-not [string]::IsNullOrWhiteSpace($ffmpegPath) -and (Test-Path -LiteralPath $ffmpegPath)) {
    $bundledToolsDir = Join-Path $publishDir "Tools\ffmpeg"
    New-Item -ItemType Directory -Force -Path $bundledToolsDir | Out-Null
    Copy-Item -LiteralPath $ffmpegPath -Destination (Join-Path $bundledToolsDir "ffmpeg.exe") -Force
}

& (Join-Path $windowsRoot "scripts\Generate-WixManifest.ps1") -PublishDir $publishDir -OutputPath $generatedWxs

$installerOutputDir = Join-Path $windowsRoot "artifacts\installer"
if (Test-Path -LiteralPath $installerOutputDir) {
    Remove-Item -LiteralPath $installerOutputDir -Recurse -Force
}

dotnet build $installerProject `
    -c Release `
    -p:UseSharedCompilation=false `
    -p:InstallerOutputName=$artifactBaseName `
    -p:InstallerVersion=$msiVersion `
    -p:AppVersion=$Version `
    -p:OutputPath="$installerOutputDir\" `
    -p:IntermediateOutputPath="$(Join-Path $windowsRoot 'artifacts\installer-obj')\"

$builtMsi = Get-ChildItem -LiteralPath $installerOutputDir -Filter "$artifactBaseName.msi" -Recurse | Select-Object -First 1
if ($null -eq $builtMsi) {
    throw "Could not find the built MSI in $installerOutputDir."
}

Copy-Item -LiteralPath $builtMsi.FullName -Destination $msiPath -Force

Compress-Archive -Path (Join-Path $publishDir '*') -DestinationPath $zipPath -Force

Write-Sha256File -Path $zipPath
Write-Sha256File -Path $msiPath

Write-Host "Created Windows release artifacts:"
Write-Host "  $zipPath"
Write-Host "  $msiPath"
