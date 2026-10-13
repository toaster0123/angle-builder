# Exercise installer control flow without downloading or installing software.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$InstallerScript = Join-Path $PSScriptRoot '../scripts/install-windows-sdk.ps1'
$OldProgramFiles = ${env:ProgramFiles(x86)}
$OldRunnerTemp = $env:RUNNER_TEMP
${env:ProgramFiles(x86)} = [System.IO.Path]::GetTempPath()
$env:RUNNER_TEMP = [System.IO.Path]::GetTempPath()

function Test-Path {
  param($Path, $PathType)
  return $global:SdkTest.Present
}
function Invoke-WebRequest {
  param($Uri, $OutFile)
  if ($Uri -notlike 'https://download.microsoft.com/*') { throw 'Unexpected source' }
  $global:SdkTest.Downloads++
}
function Get-FileHash {
  param($Path, $Algorithm)
  $hash = 'e8e264aca8bc34abdf592352bf09f986a85cdb96db0efba405ca9e149181fe61'
  if ($global:SdkTest.Case -eq 'bad-hash') { $hash = 'bad' }
  return @{ Hash = $hash }
}
function Get-AuthenticodeSignature {
  param($Path)
  $status = if ($global:SdkTest.Case -eq 'bad-signature') { 'NotTrusted' } else { 'Valid' }
  return @{ Status = $status; SignerCertificate = @{ Subject = 'CN=Microsoft Corporation, O=Microsoft Corporation' } }
}
function Start-Process {
  param($FilePath, $ArgumentList, [switch]$Wait, [switch]$PassThru)
  $global:SdkTest.Installs++
  foreach ($feature in @('OptionId.DesktopCPPx86', 'OptionId.DesktopCPPx64',
                         'OptionId.DesktopCPParm64', 'OptionId.WindowsDesktopDebuggers')) {
    if ($feature -notin $ArgumentList) { throw "Missing feature $feature" }
  }
  $global:SdkTest.Present = $global:SdkTest.Case -ne 'incomplete'
  $code = switch ($global:SdkTest.Case) {
    'installer-failure' { 1603 }
    'reboot-code' { 3010 }
    default { 0 }
  }
  return @{ ExitCode = $code }
}

try {
  $cases = @{
    'already-installed' = $null
    'fresh-install' = $null
    'reboot-code' = $null
    'bad-hash' = '*SHA256 does not match*'
    'bad-signature' = '*valid Microsoft signature*'
    'installer-failure' = '*exit code 1603*'
    'incomplete' = '*installation is incomplete*'
  }
  foreach ($case in $cases.Keys) {
    $global:SdkTest = @{ Case = $case; Present = ($case -eq 'already-installed'); Downloads = 0; Installs = 0 }
    $failure = $null
    try { & $InstallerScript } catch { $failure = $_.Exception.Message }
    if ($cases[$case]) {
      if ($failure -notlike $cases[$case]) { throw "Unexpected result for ${case}: $failure" }
    } elseif ($failure) { throw $failure }
    if ($case -eq 'already-installed' -and $global:SdkTest.Downloads -ne 0) { throw 'Unnecessary download' }
    if ($case -like 'bad-*' -and $global:SdkTest.Installs -ne 0) { throw 'Untrusted installer executed' }
    Write-Host "PASS SDK installer control flow: $case"
  }
} finally {
  ${env:ProgramFiles(x86)} = $OldProgramFiles
  $env:RUNNER_TEMP = $OldRunnerTemp
  Remove-Variable SdkTest -Scope Global -ErrorAction SilentlyContinue
}
