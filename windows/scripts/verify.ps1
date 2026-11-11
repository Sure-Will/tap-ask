param([string]$OutputDirectory)

$ErrorActionPreference = 'Stop'
$windowsRoot = Split-Path -Parent $PSScriptRoot
$solution = Join-Path $windowsRoot 'TapAsk.sln'
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

& $dotnet build $solution --configuration Release
if ($LASTEXITCODE -ne 0) { throw "dotnet build failed with exit code $LASTEXITCODE" }
& $dotnet test $solution --configuration Release --no-build
if ($LASTEXITCODE -ne 0) { throw "dotnet test failed with exit code $LASTEXITCODE" }
& (Join-Path $PSScriptRoot 'build-app.ps1') -OutputDirectory $OutputDirectory
