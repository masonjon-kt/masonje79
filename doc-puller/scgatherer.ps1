#Requires -Version 5.1
<#
.SYNOPSIS
    Gathers .docx files from immediate child folders of a root directory,
    renames each copy to the source folder name, and places them in a target folder.

.PARAMETER Root
    The root directory whose immediate child folders will be searched for .docx files.

.PARAMETER Target
    The destination folder where renamed copies will be placed.

.EXAMPLE
    .\scgatherer.ps1 -Root "C:\Projects" -Target "C:\Gathered"
#>
param(
    [Parameter(Mandatory)]
    [string]$Root,

    [Parameter(Mandatory)]
    [string]$Target
)

# Validate root
if (-not (Test-Path $Root -PathType Container)) {
    Write-Error "Root directory not found: $Root"
    exit 1
}

# Create target if it doesn't exist
if (-not (Test-Path $Target -PathType Container)) {
    New-Item -ItemType Directory -Path $Target | Out-Null
    Write-Host "Created target folder: $Target"
}

$copied = 0
$skipped = 0

# Get immediate child folders only
$folders = Get-ChildItem -Path $Root -Directory

foreach ($folder in $folders) {
    $docxFiles = Get-ChildItem -Path $folder.FullName -Filter "*.docx" -File

    if ($docxFiles.Count -eq 0) {
        continue
    }

    $index = 0
    foreach ($file in $docxFiles) {
        # Build destination name: FolderName.docx, or FolderName_2.docx if multiple
        if ($index -eq 0) {
            $destName = "$($folder.Name).docx"
        } else {
            $destName = "$($folder.Name)_$($index + 1).docx"
        }

        $destPath = Join-Path $Target $destName

        # Warn if overwriting
        if (Test-Path $destPath) {
            Write-Warning "Overwriting existing file: $destName"
        }

        Copy-Item -Path $file.FullName -Destination $destPath -Force
        Write-Host "Copied: $($file.FullName) -> $destName"
        $copied++
        $index++
    }
}

Write-Host ""
Write-Host "Done. $copied file(s) copied, $skipped skipped."
