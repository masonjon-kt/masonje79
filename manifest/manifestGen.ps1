# Get the script's directory
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition

# Base URL for files
$httpFileRoot = 'http://kremrepo.kroger.com/isilon/POS'

# Input and output file paths
$inputFile = Join-Path $scriptDir "manifestGen.txt"
$outputFile = Join-Path $scriptDir "manifest.txt"
$backupFile = Join-Path $scriptDir "manifest.txt.bak"

# Load existing manifest entries if manifest.txt exists
$existingManifest = @{}
if (Test-Path $outputFile) {
    Get-Content $outputFile | ForEach-Object {
        if ($_ -match 'name=(\S+)\s+sha1=(\S+)\s+size=(\d+)\s+url=(\S+)') {
            $name = $matches[1]
            $size = $matches[3]
            $existingManifest[$name] = @{ size = $size; line = $_ }
        }
    }
}
$newManifest = @()
Write-Host "Processing manifestGen.txt..."

$updatesMade = $false
# Read each line (file name) from manifestGen.txt
Get-Content $inputFile | ForEach-Object {
    $filePath = Join-Path $scriptDir $_
    if (Test-Path $filePath) {
        $fileName = $_
        $fileSize = (Get-Item $filePath).Length

        if ($existingManifest.ContainsKey($fileName)) {
            Write-Host "   Size: $($existingManifest[$fileName].size) vs $fileSize"
            if ($existingManifest[$fileName].size -eq $fileSize) {
                Write-Host "Skipped: $fileName (unchanged)"
                return
            } else {
                $sha1 = (Get-FileHash $filePath -Algorithm SHA1).Hash.ToLower()
                $newManifest += "name=$fileName sha1=$sha1 size=$fileSize url=$httpFileRoot/$fileName"
                Write-Host "Updated: $fileName (size changed)"
                $existingManifest.Remove($fileName)
                $updatesMade = $true
            }
        } else {
            $sha1 = (Get-FileHash $filePath -Algorithm SHA1).Hash.ToLower()
            $newManifest += "name=$fileName sha1=$sha1 size=$fileSize url=$httpFileRoot/$fileName"
            Write-Host "Added: $fileName"
            $updatesMade = $true
        }
    } else {
        Write-Warning "File not found: $filePath"
    }
}

# Add unchanged entries from the existing manifest
foreach ($entry in $existingManifest.GetEnumerator()) {
    $newManifest += $entry.Value.line
}

if (-not $updatesMade) {
    Write-Host "*** No updates made to the manifest. ***"
    exit 0
}
# Backup manifest.txt if it exists
if (Test-Path $outputFile) {
    Copy-Item -Path $outputFile -Destination $backupFile -Force
    Write-Host "Backup created: $backupFile"
}
# Write the new manifest to manifest.txt
Set-Content -Path $outputFile -Value $newManifest
Write-Host "*** Manifest updated: $outputFile ***"