[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet("Install", "Probe", "Start", "Status", "Logs", "Stop")]
    [string] $Action = "Status",

    [string] $Distribution = "Ubuntu-22.04"
)

$ErrorActionPreference = "Stop"
$modemInstancePattern = '^USB\\VID_0572&PID_1329\\'
$serviceName = "ndm24-ppp-server.service"

function Invoke-NativeChecked {
    param(
        [Parameter(Mandatory)]
        [string] $FilePath,

        [Parameter()]
        [string[]] $ArgumentList = @()
    )

    & $FilePath @ArgumentList
    if ($LASTEXITCODE -ne 0) {
        throw "$FilePath failed with exit code $LASTEXITCODE"
    }
}

function Get-Dfm56uDevice {
    $stateText = (& usbipd state) -join [Environment]::NewLine
    if ($LASTEXITCODE -ne 0) {
        throw "usbipd state failed with exit code $LASTEXITCODE"
    }
    $state = $stateText | ConvertFrom-Json
    $matches = @($state.Devices | Where-Object {
        $_.InstanceId -match $modemInstancePattern
    })
    if ($matches.Count -ne 1) {
        throw "expected one DFM-56U (0572:1329), found $($matches.Count)"
    }
    return $matches[0]
}

function Start-WslAttachWindow {
    Start-Process `
        -FilePath "wsl.exe" `
        -ArgumentList @("-d", $Distribution, "--exec", "sleep", "30") `
        -WindowStyle Hidden | Out-Null
    Start-Sleep -Seconds 2
}

function Connect-Dfm56u {
    $device = Get-Dfm56uDevice
    if ([string]::IsNullOrEmpty($device.ClientIPAddress)) {
        Start-WslAttachWindow
        Invoke-NativeChecked "usbipd" @(
            "attach", "--wsl", "--busid", $device.BusId
        )
    }

    $deviceReady = $false
    for ($attempt = 0; $attempt -lt 20; $attempt++) {
        & wsl.exe -d $Distribution -u root --exec test -c /dev/ttyACM0
        if ($LASTEXITCODE -eq 0) {
            $deviceReady = $true
            break
        }
        Start-Sleep -Milliseconds 500
    }
    if (-not $deviceReady) {
        throw "DFM-56U did not appear as /dev/ttyACM0"
    }

    # mgetty's former serial-login use has been retired. Disable it
    # defensively here too, so Start and Probe work before a reinstall.
    Invoke-NativeChecked "wsl.exe" @(
        "-d", $Distribution, "-u", "root",
        "--exec", "sh", "-c",
        "systemctl disable --now mgetty.service 2>/dev/null || true"
    )
}

function Install-PppServer {
    $installScript = Join-Path $PSScriptRoot "install-wsl.sh"
    $linuxPath = (
        & wsl.exe -d $Distribution --exec wslpath -a $installScript
    ).Trim()
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrEmpty($linuxPath)) {
        throw "could not translate the installer path for WSL"
    }
    Invoke-NativeChecked "wsl.exe" @(
        "-d", $Distribution, "-u", "root",
        "--exec", "bash", $linuxPath
    )
}

function Show-ServiceStatus {
    $device = Get-Dfm56uDevice
    [pscustomobject]@{
        BusId = $device.BusId
        Device = $device.Description
        WslAttached = -not [string]::IsNullOrEmpty($device.ClientIPAddress)
    } | Format-List

    & wsl.exe -d $Distribution -u root --exec `
        systemctl status $serviceName --no-pager
    if ($LASTEXITCODE -notin @(0, 3, 4)) {
        throw "systemctl status failed with exit code $LASTEXITCODE"
    }
}

switch ($Action) {
    "Install" {
        Install-PppServer
        Show-ServiceStatus
    }
    "Probe" {
        Connect-Dfm56u
        $probeScript = Join-Path $PSScriptRoot "probe-modem.sh"
        $linuxPath = (
            & wsl.exe -d $Distribution --exec wslpath -a $probeScript
        ).Trim()
        if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrEmpty($linuxPath)) {
            throw "could not translate the probe path for WSL"
        }
        Invoke-NativeChecked "wsl.exe" @(
            "-d", $Distribution, "-u", "root",
            "--exec", "bash", $linuxPath
        )
    }
    "Start" {
        Connect-Dfm56u
        Invoke-NativeChecked "wsl.exe" @(
            "-d", $Distribution, "-u", "root",
            "--exec", "systemctl", "restart", $serviceName
        )
        Start-Sleep -Seconds 1
        Invoke-NativeChecked "wsl.exe" @(
            "-d", $Distribution, "-u", "root",
            "--exec", "systemctl", "is-active", $serviceName
        )
        Show-ServiceStatus
    }
    "Status" {
        Show-ServiceStatus
    }
    "Logs" {
        Invoke-NativeChecked "wsl.exe" @(
            "-d", $Distribution, "-u", "root",
            "--exec", "journalctl", "-u", $serviceName,
            "--no-pager", "-n", "200"
        )
    }
    "Stop" {
        & wsl.exe -d $Distribution -u root --exec `
            systemctl stop $serviceName
        if ($LASTEXITCODE -notin @(0, 5)) {
            throw "systemctl stop failed with exit code $LASTEXITCODE"
        }

        $device = Get-Dfm56uDevice
        if (-not [string]::IsNullOrEmpty($device.ClientIPAddress)) {
            Invoke-NativeChecked "usbipd" @(
                "detach", "--busid", $device.BusId
            )
        }

        $windowsPort = $null
        for ($attempt = 0; $attempt -lt 20; $attempt++) {
            $windowsModem = Get-CimInstance Win32_POTSModem |
                Where-Object {
                    $_.PNPDeviceID -match $modemInstancePattern
                } |
                Select-Object -First 1
            if ($null -ne $windowsModem -and
                -not [string]::IsNullOrEmpty($windowsModem.AttachedTo)) {
                $windowsPort = $windowsModem.AttachedTo
                break
            }
            Start-Sleep -Milliseconds 500
        }
        if ([string]::IsNullOrEmpty($windowsPort)) {
            throw "DFM-56U did not return to a Windows COM port"
        }
        Write-Host "NDM24 PPP server stopped; DFM-56U returned as $windowsPort."
    }
}

exit 0
