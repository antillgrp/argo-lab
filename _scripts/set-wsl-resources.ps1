<#
.SYNOPSIS
    Configures WSL2 to use half of the host's total physical RAM and half of the host's CPU logical cores.

.DESCRIPTION
    This script runs on the Windows host. It queries the host machine's total RAM and CPU core count,
    calculates 50% for each, safely updates (or creates) C:\Users\<Username>\.wslconfig, and
    prompts to restart WSL so the changes take effect.

.EXAMPLE
    powershell.exe -ExecutionPolicy Bypass -File .\set-wsl-resources.ps1
#>

[CmdletBinding()]
param(
    [switch]$ForceRestart = $false
)

$ErrorActionPreference = "Stop"

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "       WSL2 Host Resource Allocation Adjuster             " -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

# 1. Query Host Resources
Write-Host "[1/4] Detecting Windows Host Hardware..." -ForegroundColor Yellow
$computerSystem = Get-CimInstance -ClassName Win32_ComputerSystem

$totalMemoryBytes = [double]$computerSystem.TotalPhysicalMemory
$totalMemoryGB    = [math]::Round($totalMemoryBytes / 1GB, 2)
$totalLogicalCPUs = [int]$computerSystem.NumberOfLogicalProcessors

Write-Host "  -> Host Total Memory : $totalMemoryGB GB" -ForegroundColor Gray
Write-Host "  -> Host Logical CPUs : $totalLogicalCPUs Cores" -ForegroundColor Gray

# 2. Calculate 50% Allocations
$targetMemoryGB = [math]::Floor($totalMemoryGB / 2)
if ($targetMemoryGB -lt 4) { $targetMemoryGB = 4 } # Keep at least 4GB for multi-node kind cluster

$targetCPUs = [math]::Floor($totalLogicalCPUs / 2)
if ($targetCPUs -lt 2) { $targetCPUs = 2 } # Keep at least 2 cores

Write-Host "`n[2/4] Target WSL2 Allocation (50% Host Resources):" -ForegroundColor Yellow
Write-Host "  -> WSL Memory: ${targetMemoryGB}GB" -ForegroundColor Green
Write-Host "  -> WSL Processors: ${targetCPUs} Cores" -ForegroundColor Green

# 3. Locate & Update .wslconfig
$wslConfigPath = Join-Path -Path $env:USERPROFILE -ChildPath ".wslconfig"
Write-Host "`n[3/4] Updating configuration file at:" -ForegroundColor Yellow
Write-Host "  $wslConfigPath" -ForegroundColor Gray

$configLines = @()
if (Test-Path -Path $wslConfigPath) {
    # Backup existing config
    $backupPath = "$wslConfigPath.bak_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
    Copy-Item -Path $wslConfigPath -Destination $backupPath -Force
    Write-Host "  (Created backup: $backupPath)" -ForegroundColor DarkGray
    $configLines = Get-Content -Path $wslConfigPath
}

$hasWsl2Section = $false
$newLines = @()
$inWsl2Section = $false
$memoryUpdated = $false
$processorsUpdated = $false

foreach ($line in $configLines) {
    $trimmed = $line.Trim()
    
    if ($trimmed -match '^\[wsl2\]') {
        $hasWsl2Section = $true
        $inWsl2Section = $true
        $newLines += $line
        continue
    }
    
    if ($inWsl2Section -and $trimmed -match '^\[.*\]') {
        # Leaving [wsl2] section; append keys if not already placed
        if (-not $memoryUpdated) {
            $newLines += "memory=${targetMemoryGB}GB"
            $memoryUpdated = $true
        }
        if (-not $processorsUpdated) {
            $newLines += "processors=$targetCPUs"
            $processorsUpdated = $true
        }
        $inWsl2Section = $false
        $newLines += $line
        continue
    }
    
    if ($inWsl2Section) {
        if ($trimmed -match '^memory\s*=') {
            $newLines += "memory=${targetMemoryGB}GB"
            $memoryUpdated = $true
            continue
        }
        if ($trimmed -match '^processors\s*=') {
            $newLines += "processors=$targetCPUs"
            $processorsUpdated = $true
            continue
        }
    }
    
    $newLines += $line
}

# If [wsl2] section was completely missing
if (-not $hasWsl2Section) {
    $newLines += "[wsl2]"
    $newLines += "memory=${targetMemoryGB}GB"
    $newLines += "processors=$targetCPUs"
    $newLines += "networkingMode=mirrored"
} else {
    # If [wsl2] was at the end of the file and keys weren't placed yet
    if (-not $memoryUpdated) {
        $newLines += "memory=${targetMemoryGB}GB"
    }
    if (-not $processorsUpdated) {
        $newLines += "processors=$targetCPUs"
    }
}

Set-Content -Path $wslConfigPath -Value $newLines -Encoding UTF8
Write-Host "  -> Successfully updated .wslconfig!" -ForegroundColor Green

# 4. WSL Restart Prompt
Write-Host "`n[4/4] Restart WSL for changes to apply:" -ForegroundColor Yellow
if ($ForceRestart) {
    Write-Host "  Restarting WSL..." -ForegroundColor Cyan
    wsl.exe --shutdown
    Write-Host "  WSL has been shut down. It will restart automatically upon next terminal launch." -ForegroundColor Green
} else {
    $choice = Read-Host "Would you like to restart WSL now (wsl --shutdown)? (y/n)"
    if ($choice -eq 'y' -or $choice -eq 'Y') {
        wsl.exe --shutdown
        Write-Host "  WSL shut down successfully. Reopen your terminal to start with the new allocations." -ForegroundColor Green
    } else {
        Write-Host "  Restart skipped. Please run 'wsl --shutdown' from PowerShell when ready." -ForegroundColor Gray
    }
}

Write-Host "`nDone!" -ForegroundColor Cyan
