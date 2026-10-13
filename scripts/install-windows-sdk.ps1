# Install the SDK required by the pinned Chromium toolchain on hosted CI runners.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$SdkVersion = '10.0.28000.0'
$SdkRoot = Join-Path ${env:ProgramFiles(x86)} 'Windows Kits\10'
$RequiredFiles = @(
  "Include\$SdkVersion\um\Windows.h",
  "Include\$SdkVersion\shared\sdkddkver.h",
  "Include\$SdkVersion\ucrt\stdio.h",
  "bin\$SdkVersion\x64\rc.exe"
)
foreach ($arch in @('x86', 'x64', 'arm64')) {
  $RequiredFiles += "Lib\$SdkVersion\um\$arch\kernel32.lib"
  $RequiredFiles += "Lib\$SdkVersion\ucrt\$arch\ucrt.lib"
  $RequiredFiles += "Debuggers\$arch\dbghelp.dll"
}

function Get-MissingSdkFiles {
  @($RequiredFiles | Where-Object {
    -not (Test-Path (Join-Path $SdkRoot $_) -PathType Leaf)
  })
}

if (@(Get-MissingSdkFiles).Count -eq 0) {
  Write-Host "Windows SDK $SdkVersion is already installed"
  exit 0
}

# Official September 2026 SDK servicing release:
# https://learn.microsoft.com/en-us/windows/apps/windows-sdk/downloads
$InstallerUrl = 'https://download.microsoft.com/download/e6cfffdc-0d3e-4c6c-96d7-d491da459a07/KIT_BUNDLE_WINDOWSSDK_MEDIACREATION/winsdksetup.exe'
$ExpectedSha256 = 'e8e264aca8bc34abdf592352bf09f986a85cdb96db0efba405ca9e149181fe61'
$Installer = Join-Path $env:RUNNER_TEMP 'winsdksetup-28000.exe'
Invoke-WebRequest -Uri $InstallerUrl -OutFile $Installer
if ((Get-FileHash $Installer -Algorithm SHA256).Hash -ne $ExpectedSha256) {
  throw 'Windows SDK installer SHA256 does not match the pinned Microsoft installer'
}
$Signature = Get-AuthenticodeSignature $Installer
if ($Signature.Status -ne 'Valid' -or
    $Signature.SignerCertificate.Subject -notmatch 'O=Microsoft Corporation') {
  throw 'Windows SDK installer does not have a valid Microsoft signature'
}

$InstallArgs = @(
  '/quiet', '/norestart', '/ceip', 'off', '/features',
  'OptionId.DesktopCPPx86', 'OptionId.DesktopCPPx64',
  'OptionId.DesktopCPParm64', 'OptionId.WindowsDesktopDebuggers'
)
$Process = Start-Process -FilePath $Installer -ArgumentList $InstallArgs -Wait -PassThru
if ($Process.ExitCode -notin @(0, 3010)) {
  throw "Windows SDK installation failed with exit code $($Process.ExitCode)"
}
$Missing = @(Get-MissingSdkFiles)
if ($Missing.Count -ne 0) {
  throw "Windows SDK installation is incomplete: $($Missing -join ', ')"
}
Write-Host "Verified Windows SDK $SdkVersion headers, libraries, tools and debuggers"
