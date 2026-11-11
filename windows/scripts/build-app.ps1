param([string]$OutputDirectory, [string]$Version)

$ErrorActionPreference = 'Stop'
$windowsRoot = Split-Path -Parent $PSScriptRoot
$project = Join-Path $windowsRoot 'src/TapAsk/TapAsk.csproj'
$output = if ($OutputDirectory) { $OutputDirectory } else { Join-Path $windowsRoot 'build/app' }
$command = Get-Command dotnet -ErrorAction SilentlyContinue
if ($command) {
    $dotnet = $command.Source
} else {
    $repoRoot = Split-Path -Parent $windowsRoot
    $env:DOTNET_ROOT = Join-Path $repoRoot 'private/dotnet'
    $env:DOTNET_CLI_HOME = Join-Path $repoRoot 'private/dotnet-home'
    $env:NUGET_PACKAGES = Join-Path $repoRoot 'private/nuget-packages'
    $dotnet = Join-Path $env:DOTNET_ROOT 'dotnet.exe'
    if (-not (Test-Path -LiteralPath $dotnet)) { throw '.NET 10 SDK not found.' }
}

$publishArgs = @('publish', $project, '--configuration', 'Release', '--runtime', 'win-x64', '--self-contained', 'true', '--output', $output)
if ($Version) {
    $publishArgs += "-p:Version=$Version"
    $publishArgs += '-p:IncludeSourceRevisionInInformationalVersion=false'
}
& $dotnet @publishArgs
if ($LASTEXITCODE -ne 0) { throw "dotnet publish failed with exit code $LASTEXITCODE" }
Write-Host "TapAsk: $output"
