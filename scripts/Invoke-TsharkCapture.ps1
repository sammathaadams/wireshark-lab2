# ==============================================================================
# Invoke-TsharkCapture.ps1
# Lab 2 — Automated Packet Capture with tshark
#
# PURPOSE:
#   Wraps the tshark CLI (installed with Wireshark) to automate a timed
#   packet capture and save the result as a .pcapng file. Useful for capturing
#   on a Windows machine without opening the Wireshark GUI, or for scripting
#   captures as part of an automation pipeline.
#
# USAGE:
#   # Capture 500 packets on the auto-detected active interface (30-second timeout)
#   .\Invoke-TsharkCapture.ps1
#
#   # Specify interface name and output file explicitly
#   .\Invoke-TsharkCapture.ps1 -Interface "Wi-Fi" -OutputFile "C:\captures\test.pcapng" -PacketCount 200
#
#   # Capture with a display filter (only DNS traffic)
#   .\Invoke-TsharkCapture.ps1 -CaptureFilter "port 53" -OutputFile "dns-only.pcapng"
#
# REQUIREMENTS:
#   - Wireshark must be installed using the official installer (Npcap is bundled):
#     Invoke-WebRequest -Uri "https://2.na.dl.wireshark.org/win64/Wireshark-latest-x64.exe" -OutFile "$env:TEMP\wireshark-installer.exe"
#     Start-Process -FilePath "$env:TEMP\wireshark-installer.exe" -Wait
#     Accept all defaults — Npcap installs automatically as part of the same wizard.
#   - Run from an elevated PowerShell session (required for packet capture)
# ==============================================================================

param(
    [string] $Interface   = "",
    [string] $OutputFile  = "capture_$(Get-Date -Format 'yyyyMMdd_HHmmss').pcapng",
    [int]    $PacketCount = 500,
    [int]    $DurationSec = 30,
    [string] $CaptureFilter = ""   # BPF capture filter, e.g. "port 53" or "host 8.8.8.8"
)

# ------------------------------------------------------------------------------
# Locate tshark
# ------------------------------------------------------------------------------
$tsharkPath = "C:\Program Files\Wireshark\tshark.exe"

if (-not (Test-Path $tsharkPath)) {
    Write-Error "tshark not found at '$tsharkPath'. Ensure Wireshark is installed."
    exit 1
}

Write-Host "tshark found: $tsharkPath" -ForegroundColor Green

# ------------------------------------------------------------------------------
# List available interfaces if none specified
# ------------------------------------------------------------------------------
if ($Interface -eq "") {
    Write-Host "`nAvailable interfaces:" -ForegroundColor Cyan
    & $tsharkPath -D
    Write-Host ""

    # Auto-select the first non-loopback interface
    $interfaceList = & $tsharkPath -D 2>&1
    $selected = $interfaceList | Where-Object { $_ -notmatch "loopback|Npcap Loopback" } | Select-Object -First 1

    if ($selected -match "^(\d+)\.\s+(.+)") {
        $Interface = $Matches[2].Trim()
        # Remove trailing parenthetical description if present
        $Interface = ($Interface -split "\(")[0].Trim()
        Write-Host "Auto-selected interface: $Interface" -ForegroundColor Yellow
    } else {
        Write-Error "Could not auto-detect an active interface. Specify -Interface explicitly."
        exit 1
    }
}

# ------------------------------------------------------------------------------
# Build tshark arguments
# ------------------------------------------------------------------------------
$tsharkArgs = @(
    "-i", $Interface,
    "-w", $OutputFile,
    "-c", $PacketCount,
    "-a", "duration:$DurationSec"
)

# Add a BPF capture filter if specified
if ($CaptureFilter -ne "") {
    $tsharkArgs += "-f"
    $tsharkArgs += $CaptureFilter
    Write-Host "Capture filter applied: $CaptureFilter" -ForegroundColor Cyan
}

# ------------------------------------------------------------------------------
# Run the capture
# ------------------------------------------------------------------------------
Write-Host ""
Write-Host "Starting capture..." -ForegroundColor Green
Write-Host "  Interface : $Interface"
Write-Host "  Output    : $OutputFile"
Write-Host "  Max pkts  : $PacketCount"
Write-Host "  Timeout   : $DurationSec seconds"
Write-Host ""
Write-Host "Generate traffic now (open a browser, run nslookup, ping, etc.)"
Write-Host "Capture will stop automatically after $DurationSec seconds or $PacketCount packets."
Write-Host ""

$process = Start-Process -FilePath $tsharkPath `
    -ArgumentList $tsharkArgs `
    -NoNewWindow `
    -Wait `
    -PassThru

# ------------------------------------------------------------------------------
# Results
# ------------------------------------------------------------------------------
if ($process.ExitCode -eq 0) {
    Write-Host ""
    Write-Host "Capture complete." -ForegroundColor Green
    Write-Host "Saved to: $(Resolve-Path $OutputFile)" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "To open in Wireshark GUI:"
    Write-Host "  Start-Process 'C:\Program Files\Wireshark\Wireshark.exe' -ArgumentList '$OutputFile'"
    Write-Host ""
    Write-Host "To inspect summary from terminal:"
    Write-Host "  & '$tsharkPath' -r '$OutputFile' -q -z io,phs"
} else {
    Write-Error "tshark exited with code $($process.ExitCode). Check interface name and permissions."
}
