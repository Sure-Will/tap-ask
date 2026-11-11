$ErrorActionPreference = 'Stop'
$windowsRoot = Split-Path -Parent $PSScriptRoot
$repoRoot = Split-Path -Parent $windowsRoot
$inputPath = Join-Path $repoRoot 'macos/Resources/AppIcon.icns'
$outputPath = Join-Path $windowsRoot 'src/TapAsk/Resources/TapAsk.ico'
$bytes = [IO.File]::ReadAllBytes($inputPath)

function Read-BigEndianInt([byte[]]$data, [int]$offset) {
    $value = [byte[]]@($data[$offset], $data[$offset + 1], $data[$offset + 2], $data[$offset + 3])
    [Array]::Reverse($value)
    return [BitConverter]::ToInt32($value, 0)
}

$images = [ordered]@{}
$offset = 8
while ($offset -lt $bytes.Length) {
    $length = Read-BigEndianInt $bytes ($offset + 4)
    if ($length -lt 8 -or $offset + $length -gt $bytes.Length) { throw 'Invalid ICNS chunk.' }
    $start = $offset + 8
    $count = $length - 8
    if ($count -ge 24 -and [BitConverter]::ToString($bytes, $start, 8) -eq '89-50-4E-47-0D-0A-1A-0A') {
        $width = Read-BigEndianInt $bytes ($start + 16)
        $height = Read-BigEndianInt $bytes ($start + 20)
        $key = [string]$width
        if ($width -eq $height -and $width -le 256 -and -not $images.Contains($key)) {
            $png = [byte[]]::new($count)
            [Array]::Copy($bytes, $start, $png, 0, $count)
            $images[$key] = $png
        }
    }
    $offset += $length
}
if ($images.Count -eq 0) { throw 'No compatible PNG icons were found in the ICNS file.' }

[IO.Directory]::CreateDirectory((Split-Path -Parent $outputPath)) | Out-Null
$stream = [IO.File]::Create($outputPath)
$writer = [IO.BinaryWriter]::new($stream)
try {
    $writer.Write([uint16]0); $writer.Write([uint16]1); $writer.Write([uint16]$images.Count)
    $imageOffset = 6 + 16 * $images.Count
    foreach ($entry in $images.GetEnumerator()) {
        $dimension = if ([int]$entry.Key -eq 256) { 0 } else { [int]$entry.Key }
        $writer.Write([byte]$dimension); $writer.Write([byte]$dimension)
        $writer.Write([byte]0); $writer.Write([byte]0)
        $writer.Write([uint16]1); $writer.Write([uint16]32)
        $writer.Write([uint32]$entry.Value.Length); $writer.Write([uint32]$imageOffset)
        $imageOffset += $entry.Value.Length
    }
    foreach ($entry in $images.GetEnumerator()) { $writer.Write([byte[]]$entry.Value) }
} finally { $writer.Dispose() }
Write-Host "Generated $outputPath from the existing Mac icon."
