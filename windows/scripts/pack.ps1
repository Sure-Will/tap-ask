param(
    [Parameter(Mandatory = $true)][string]$Version,
    [string]$OutputDirectory
)

$ErrorActionPreference = 'Stop'
$windowsRoot = Split-Path -Parent $PSScriptRoot
$repoRoot = Split-Path -Parent $windowsRoot
$appDirectory = Join-Path $windowsRoot 'build/package-app'
$releases = if ($OutputDirectory) { $OutputDirectory } else { Join-Path $windowsRoot 'build/releases' }
$command = Get-Command vpk -ErrorAction SilentlyContinue
if ($command) {
    $vpk = $command.Source
} else {
    $vpk = Join-Path $repoRoot 'private/vpk/vpk.exe'
    if (-not (Test-Path -LiteralPath $vpk)) { throw 'Velopack vpk 1.2.161 not found.' }
    $env:DOTNET_ROOT = Join-Path $repoRoot 'private/dotnet'
}

& (Join-Path $PSScriptRoot 'build-app.ps1') -OutputDirectory $appDirectory -Version $Version
$builtVersion = (Get-Item -LiteralPath (Join-Path $appDirectory 'TapAsk.exe')).VersionInfo.ProductVersion
if ($builtVersion -ne $Version) { throw "App version '$builtVersion' does not match package version '$Version'." }
& $vpk pack --packId TapAsk --packTitle TapAsk --packVersion $Version --packDir $appDirectory `
    --mainExe TapAsk.exe --runtime win-x64 --channel win --icon (Join-Path $windowsRoot 'src/TapAsk/Resources/TapAsk.ico') --outputDir $releases
if ($LASTEXITCODE -ne 0) { throw "vpk pack failed with exit code $LASTEXITCODE" }
Write-Host "Local packages: $releases"
