$ErrorActionPreference = 'Stop'

$scriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
$apkPath = Join-Path $scriptDirectory 'Wi-Fi-ON.apk'
$packageName = 'io.github.ksuzukigh.rokidwifion'
$platformToolsUrl = 'https://dl.google.com/android/repository/platform-tools-latest-windows.zip'
$installRoot = Join-Path $env:LOCALAPPDATA 'Rokid-Wi-Fi-ON'
$platformToolsDirectory = Join-Path $installRoot 'platform-tools'
$adbPath = Join-Path $platformToolsDirectory 'adb.exe'

function Stop-Installer {
    param([int]$ExitCode = 1)

    Write-Host
    Read-Host 'Press Enter to close this window' | Out-Null
    exit $ExitCode
}

function Invoke-Adb {
    param([Parameter(Mandatory = $true)][string[]]$Arguments)

    $output = @(& $adbPath @Arguments 2>&1)
    if ($LASTEXITCODE -ne 0) {
        $message = ($output -join [Environment]::NewLine).Trim()
        if ([string]::IsNullOrWhiteSpace($message)) {
            $message = "adb exited with code $LASTEXITCODE."
        }
        throw $message
    }

    return $output
}

function Get-AdbDevices {
    $output = @(& $adbPath devices 2>$null)
    if ($LASTEXITCODE -ne 0) {
        return @()
    }

    $devices = @()
    foreach ($line in $output) {
        if ($line -match '^\s*(?<serial>\S+)\s+(?<state>\S+)\s*$') {
            $devices += [pscustomobject]@{
                Serial = $Matches.serial
                State = $Matches.state
            }
        }
    }

    return $devices
}

function Get-DeviceProperty {
    param(
        [Parameter(Mandatory = $true)][string]$Serial,
        [Parameter(Mandatory = $true)][string]$PropertyName
    )

    $output = @(& $adbPath -s $Serial shell getprop $PropertyName 2>$null)
    if ($LASTEXITCODE -ne 0) {
        return ''
    }

    return ($output -join "`n").Trim()
}

function Find-RokidDevice {
    $devices = @(Get-AdbDevices)
    $readyDevices = @($devices | Where-Object { $_.State -eq 'device' })

    foreach ($device in $readyDevices) {
        $model = Get-DeviceProperty -Serial $device.Serial -PropertyName 'ro.product.model'
        $manufacturer = Get-DeviceProperty -Serial $device.Serial -PropertyName 'ro.product.manufacturer'
        if ($model -eq 'RG-glasses' -and $manufacturer -eq 'Rokid') {
            return [pscustomobject]@{
                Serial = $device.Serial
                Model = $model
                Manufacturer = $manufacturer
                IsRokid = $true
            }
        }
    }

    # If exactly one device is connected, let the user confirm it below.
    if ($readyDevices.Count -eq 1) {
        $device = $readyDevices[0]
        return [pscustomobject]@{
            Serial = $device.Serial
            Model = Get-DeviceProperty -Serial $device.Serial -PropertyName 'ro.product.model'
            Manufacturer = Get-DeviceProperty -Serial $device.Serial -PropertyName 'ro.product.manufacturer'
            IsRokid = $false
        }
    }

    return $null
}

function Ensure-Adb {
    $requiredFiles = @('adb.exe', 'AdbWinApi.dll', 'AdbWinUsbApi.dll')
    $allFilesPresent = $true
    foreach ($fileName in $requiredFiles) {
        if (-not (Test-Path -LiteralPath (Join-Path $platformToolsDirectory $fileName))) {
            $allFilesPresent = $false
            break
        }
    }

    if ($allFilesPresent) {
        return
    }

    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $temporaryDirectory = Join-Path ([IO.Path]::GetTempPath()) ('rokid-wifi-on-' + [Guid]::NewGuid().ToString('N'))
    $zipPath = Join-Path $temporaryDirectory 'platform-tools.zip'

    try {
        New-Item -ItemType Directory -Path $temporaryDirectory -Force | Out-Null
        Write-Host 'Downloading Android Platform-Tools from Google...' -ForegroundColor Cyan
        Invoke-WebRequest -UseBasicParsing -Uri $platformToolsUrl -OutFile $zipPath

        Expand-Archive -LiteralPath $zipPath -DestinationPath $temporaryDirectory -Force
        $extractedDirectory = Join-Path $temporaryDirectory 'platform-tools'
        if (-not (Test-Path -LiteralPath (Join-Path $extractedDirectory 'adb.exe'))) {
            throw 'The downloaded Platform-Tools archive did not contain adb.exe.'
        }

        New-Item -ItemType Directory -Path $platformToolsDirectory -Force | Out-Null
        Get-ChildItem -LiteralPath $extractedDirectory | Copy-Item -Destination $platformToolsDirectory -Recurse -Force
    }
    finally {
        if (Test-Path -LiteralPath $temporaryDirectory) {
            Remove-Item -LiteralPath $temporaryDirectory -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    foreach ($fileName in $requiredFiles) {
        if (-not (Test-Path -LiteralPath (Join-Path $platformToolsDirectory $fileName))) {
            throw "Platform-Tools installation is incomplete: $fileName is missing."
        }
    }
}

try {
    if (-not (Test-Path -LiteralPath $apkPath)) {
        throw 'Wi-Fi-ON.apk was not found. Keep this installer in the same folder as the APK.'
    }

    Ensure-Adb

    Write-Host
    Write-Host 'Connect Rokid AI Glasses RV101 with the development 5-pin USB cable.' -ForegroundColor Cyan
    Write-Host 'Disconnect other Android devices from this PC.'
    Write-Host 'Waiting up to 60 seconds for an authorized ADB device...' -ForegroundColor Cyan

    $rokidDevice = $null
    $unauthorizedMessageShown = $false
    for ($attempt = 0; $attempt -lt 60 -and $null -eq $rokidDevice; $attempt++) {
        $rokidDevice = Find-RokidDevice
        if ($null -ne $rokidDevice) {
            break
        }

        if (-not $unauthorizedMessageShown) {
            $unauthorizedDevices = @(Get-AdbDevices | Where-Object { $_.State -eq 'unauthorized' })
            if ($unauthorizedDevices.Count -gt 0) {
                Write-Host
                Write-Host 'Approve the USB debugging prompt on Rokid, then wait here.' -ForegroundColor Yellow
                $unauthorizedMessageShown = $true
            }
        }

        Start-Sleep -Seconds 1
    }

    if ($null -eq $rokidDevice) {
        throw 'Rokid was not detected. Confirm ADB mode, the development cable, the USB debugging prompt, and the Windows USB driver.'
    }

    Write-Host
    Write-Host "Connected device: $($rokidDevice.Manufacturer) $($rokidDevice.Model) [$($rokidDevice.Serial)]"
    if (-not $rokidDevice.IsRokid) {
        Write-Host 'The connected device could not be identified as Rokid RG-glasses.' -ForegroundColor Yellow
        $confirmation = Read-Host 'If this is the intended Rokid device, type y and press Enter'
        if ($confirmation -notmatch '^(y|yes)$') {
            throw 'Installation cancelled.'
        }
    }

    Write-Host
    Write-Host 'This installer will:'
    Write-Host '  1. Install or update Wi-Fi ON.'
    Write-Host '  2. Grant the permission needed to restore Rokid Control after reboot.'
    $confirmation = Read-Host 'Type y and press Enter to continue'
    if ($confirmation -notmatch '^(y|yes)$') {
        throw 'Installation cancelled.'
    }

    Write-Host 'Installing Wi-Fi ON...' -ForegroundColor Cyan
    Invoke-Adb -Arguments @('-s', $rokidDevice.Serial, 'install', '-r', $apkPath) | Out-Null

    Write-Host 'Configuring Rokid Control recovery...' -ForegroundColor Cyan
    Invoke-Adb -Arguments @('-s', $rokidDevice.Serial, 'shell', 'pm', 'grant', $packageName, 'android.permission.WRITE_SECURE_SETTINGS') | Out-Null

    Write-Host
    Write-Host 'Installation completed successfully.' -ForegroundColor Green
    Write-Host 'Open Wi-Fi ON from the Rokid app list to restore Wi-Fi.'
    Stop-Installer -ExitCode 0
}
catch {
    Write-Host
    Write-Host "Installation failed: $($_.Exception.Message)" -ForegroundColor Red
    Stop-Installer -ExitCode 1
}
