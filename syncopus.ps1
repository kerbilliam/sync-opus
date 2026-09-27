[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$SourceDir,

    [Parameter(Position = 1)]
    [string]$DestinationDir,

    [int]$Bitrate = 128,
    
    [int]$ThrottleLimit = [Math]::Floor([Environment]::ProcessorCount / 2),
    
    [switch]$NoPic,
    [switch]$Help
)

function Write-End {
    param(
        [string]$ErrMsg
    )
    Write-Warning $ErrMsg
    exit 1
}

function Write-Usage {
	Write-Output "Writing help..."
    exit 0
}

if ($Help) {
    # add option descriptions later
    Write-Usage
}

# Ensure opusenc is installed
if (-not (Get-Command opusenc -ErrorAction SilentlyContinue)) {
    Write-Error "opusenc not found"
    Write-Host "Please install opus-tools for opusenc.exe"
    exit 1
}

# Ensure directories exist and are valid
if ([string]::IsNullOrWhiteSpace($SourceDir)) {
    Write-End "Please provide a source directory."
} else {
    $ResPath = Resolve-Path -LiteralPath $SourceDir -ErrorAction SilentlyContinue
    if (($null -ne $ResPath) -and (Test-Path -PathType Container $ResPath)) {
        $SourceDir = $ResPath
    } else {
        Write-End "'$SourceDir' is not a valid directory"
    }
}

if ([string]::IsNullOrWhiteSpace($DestinationDir)) {
    Write-End "Please provide a destination directory."
} else {
    # Create dest dir if not exist
    if (-not (Test-Path -PathType Container $DestinationDir)) {
        New-Item -ItemType Directory $DestinationDir
    }
    $DestinationDir = Resolve-Path -LiteralPath $DestinationDir
}

# Get all items and count
$allItems = Get-ChildItem -LiteralPath $SourceDir -Recurse
$totalItems = $allItems.Count

if ($totalItems -eq 0) {
    Write-Host "No files or directories found to process."
    exit 0
}

# Mirror source dir directory structure beforehand
$allItems | Where-Object { $_.PSIsContainer } | ForEach-Object {
    $relPath = $_.FullName.Substring($SourceDir.Length)
    $targetPath = Join-Path -Path $DestinationDir -ChildPath $relPath

    if (-not (Test-Path -LiteralPath $targetPath)) {
        New-Item -ItemType Directory $targetPath -Force
    }
}

# set nopic flag
$NoPicFlag = if ($NoPic) { '--discard-pictures' } else { "" }

$allItems | Where-Object { -not $_.PSIsContainer } | ForEach-Object -Parallel {
    $file = $_
    $srcRoot = $using:SourceDir
    $destRoot = $using:DestinationDir
    $bitrate = $using:Bitrate
    $nopic = $using:NoPicFlag

    # Reconstruct destination path
    $relativePath = $file.FullName.Substring($srcRoot.Length)
    
    if ($file.Extension -in '.flac', '.wav') {
        $opusFile = $relativePath -replace '\.[^.]+$', '.opus'
        $targetOpus = Join-Path -Path $destRoot -ChildPath $opusFile
        
        $ShouldEncode = $true
        if (Test-Path -Path $targetOpus) {
            $TargetItem = Get-Item -Path $targetOpus
            if ($file.LastWriteTimeUtc -le $TargetItem.LastWriteTimeUtc) {
                $ShouldEncode = $false
            }
        }
        
        if ($ShouldEncode) {
            $ArgsList = @('--quiet', '--bitrate', $bitrate, '--vbr')
            if ($nopic) { $ArgsList += $nopic}
            $ArgsList += @($file.FullName, $targetOpus)
            
            & opusenc @ArgsList 
        }

    }
    else {
        $targetCopy = Join-Path -Path $destRoot -ChildPath $relativePath        
        $ShouldCopy = $true
        if (Test-Path -Path $targetCopy) {
            $TargetItem = Get-Item -Path $targetCopy
            if ($file.LastWriteTimeUtc -le $TargetItem.LastWriteTimeUtc) {
                $ShouldCopy = $false
            }
        }
        
        if ($ShouldCopy) {
            Copy-Item -Path $file.FullName -Destination $targetCopy -Force
        }
    }
} -ThrottleLimit $ThrottleLimit

Write-Host 'syncopus: Mirror complete!' -ForegroundColor Green

