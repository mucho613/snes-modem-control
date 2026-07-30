param(
    [string]$Distribution = "Ubuntu-22.04",
    [string]$BusId = "6-3"
)

$ErrorActionPreference = "Stop"

$workspace = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$usbState = (& usbipd.exe list | Select-String -SimpleMatch $BusId).Line
if (-not $usbState) {
    throw "USB bus ID $BusId was not found; run usbipd list and pass the DFM-56U bus ID"
}
if ($usbState -notmatch "Attached") {
    & usbipd.exe attach --wsl $Distribution --busid $BusId
    if ($LASTEXITCODE -ne 0) {
        throw "failed to attach DFM-56U bus $BusId to $Distribution"
    }
}

$wslWorkspace = (& wsl.exe -d $Distribution --exec wslpath -a $workspace).Trim()
if (-not $wslWorkspace) {
    throw "could not translate workspace path for WSL"
}

& wsl.exe -d $Distribution -u root --exec `
    python3 "$wslWorkspace/tools/nifty-reference/nifty_reference.py"
exit $LASTEXITCODE
