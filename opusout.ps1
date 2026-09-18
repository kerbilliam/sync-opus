param(
    [Parameter(Mandatory = $true)]
    [string]$SourceDir,

    [Parameter(Mandatory = $true)]
    [string]$DestinationDir,

    [int]$Bitrate = 128,
    
    [int]$ThrottleLimit = [Math]::Floor([Environment]::ProcessorCount / 2)
)

# Ensure absolute paths
$SourceDir = Resolve-Path -LiteralPath $SourceDir
$DestinationDir = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($DestinationDir)

$allItems = Get-ChildItem -LiteralPath $SourceDir -Recurse
$totalItems = $allItems.Count

if ($totalItems -eq 0) {
    Write-Host "No files or directories found to process."
    return
}

# thread-safe counter
$completedCount = 0

$allItems | ForEach-Object -Parallel {
    $item = $_
    $srcRoot = $using:SourceDir
    $destRoot = $using:DestinationDir
    $bitrate = $using:Bitrate

    # Reconstruct destination path
    $relativePath = $item.FullName.Substring($srcRoot.Length)
    $targetPath = Join-Path $destRoot $relativePath

    if ($item.PSIsContainer) {
        # Create corresponding destination directory
        if (-not (Test-Path $targetPath)) {
            New-Item -ItemType Directory -Path $targetPath -Force | Out-Null
        }
    }
    else {
        # Ensure parent folder exists
        $parentDir = Split-Path $targetPath
        if (-not (Test-Path $parentDir)) {
            New-Item -ItemType Directory -Path $parentDir -Force | Out-Null
        }

        # Transcode .flac and .wav files
        if ($item.Extension -match '^\.(flac|wav)$') {
            $opusPath = [System.IO.Path]::ChangeExtension($targetPath, '.opus')

            if (-not (Test-Path $opusPath)) {
                # Run opusenc
                opusenc --bitrate $bitrate --quiet "$($item.FullName)" "$opusPath"
            }
        }
        else {
            # Mirror non-audio files as-is
            if (-not (Test-Path $targetPath)) {
                Copy-Item -LiteralPath $item.FullName -Destination $targetPath
            }
        }
    }

    return $true

} -ThrottleLimit $ThrottleLimit | ForEach-Object {
    $completedCount++
    $percent = [math]::Min(100, [int](($completedCount / $totalItems) * 100))

    Write-Progress -Activity "Mirroring & Encoding Audio" `
        -Status "Processing $completedCount / $totalItems files ($percent%)" `
        -PercentComplete $percent
}

Write-Progress -Activity "Mirroring & Encoding Audio" -Completed

