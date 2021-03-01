function main {
    # admin priveleges required to extract setup program
    $url = 'https://www.microsoft.com/en-us/download/confirmation.aspx?id=49117'
    $FileName = 'officedeploymenttool.exe'
    $url = ((Invoke-WebRequest -Uri $url -UseBasicParsing).links |
    where-object "data-bi-cN" -like '*click here to download manually*').href

    #region create location to download installer
    $ParentDir = "$PsScriptRoot\output"
    $tmpDir = "$ParentDir\Tmp"
    if (Test-Path $ParentDir) {}
    else { $null = New-Item $ParentDir -ItemType Directory }
    if (Test-Path $tmpDir ) {}
    else { $null = New-Item $tmpDir -ItemType Directory }
    #endregion create location to download installer

    # download the latest installation
    (New-Object System.Net.WebClient).DownloadFile("$url", "$tmpDir\$FileName")

    # extract setup program
    $ExtractSetup = Start-Process -FilePath "$tmpDir\$FileName" -ArgumentList "/quiet /extract:$ParentDir" -Wait -PassThru -WindowStyle Hidden
    if ($ExtractSetup.ExitCode -eq 0) { Remove-Item $tmpDir -Force -Confirm:$false -Recurse } 
    else { throw "Setup extract failed" }

    # create config file
    $DlconfigXML = $configXML -replace "<SOURCEDIR>", $ParentDir
    $configfile = "$ParentDir\configuration.xml"
    $DlconfigXML | Out-File -FilePath $configfile

    # download media from cdn
    $DownloadMedia = Start-Process -FilePath "$ParentDir\setup.exe" -ArgumentList "/download `"$configfile`"" -WindowStyle Hidden -PassThru -Wait
    If ($DownloadMedia.ExitCode -eq 0) {
        $AppVersion = (Get-ChildItem "$ParentDir\Office\Data" -Directory | Where-Object {$_.name -as [version]}).Name
        #region create install.ps1 script
        $ScriptTemplate = $ScriptTemplate -replace "<ConfigXml>", $configXML
        $ScriptTemplate = $ScriptTemplate -replace "<SOURCEDIR>", '$PSScriptRoot'
        $ScriptTemplate = $ScriptTemplate -replace "<AppVersion>", $AppVersion
        $ScriptTemplate | Out-File -FilePath "$PSscriptRoot\output\install.ps1"
        #endregion create install.ps1 script
    }
    else { throw "Setup download failed" }
    Remove-Item "$ParentDir\configuration.xml" -Force

}
$configXML = @"
<Configuration>
  <Info Description="Office 365" />
  <Add OfficeClientEdition="64" Channel="SemiAnnual" SourcePath="<SOURCEDIR>">
    <Product ID="O365ProPlusRetail">
      <Language ID="en-us" />
      <Language ID="nb-no" />
      <ExcludeApp ID="OneDrive" />
      <ExcludeApp ID="Groove" />
      <ExcludeApp ID="Lync" />
      <ExcludeApp ID="Teams" />
      <ExcludeApp ID="Bing" />
    </Product>
    <Product ID="LanguagePack">
      <Language ID="en-us" />
      <Language ID="nb-no" />
    </Product>
    <Product ID="ProofingTools">
      <Language ID="en-us" />
      <Language ID="nb-no" />
    </Product>
  </Add>
  <Property Name="FORCEAPPSHUTDOWN" Value="TRUE" />
  <Property Name="PinIconsToTaskbar" Value="FALSE" />
  <Property Name="SharedComputerLicensing" Value="1" />
  <Display Level="None" AcceptEULA="TRUE" />
  <Logging Level="Standard" Path="C:\Windows\Logs" />
</Configuration>
"@
$ScriptTemplate = @'
<#PSScriptInfo
.VERSION
    2.0
.AUTHOR
    Self-packaged
.DATE
.NOTE
Includes:
    Office 365 / Excel
    Office 365 / Powerpoint
    Office 365 / Word
    Office 365 / OneNote
    Office 365 / Outlook
    Office 365 / Publisher
    Office 365 / Access
.PREREQUISITES
    N/A
.EXTERNAL CONFIGURATION ITEMS
    N/A
#>

# Provide Package Name to be used in logging and output
$PkgName = 'Microsoft-Office-365-ProPlus-x64'
function Start-ProductInstall {
    [CmdletBinding()]
    param()
#region // PUT REQUIRED CODE FOR INSTALLATION BELOW THIS LINE // ****************************************************
$ProductName = "Microsoft Office 365 ProPlus*"
$ProductVersion = "<AppVersion>"

$configuration = @"
<ConfigXml>
"@
$configfile = "$env:TEMP\configuration.xml"
$configuration | Out-File -FilePath $configfile

if (-not (Get-InstalledSoftware -DisplayName $ProductName -DisplayVersion $ProductVersion)) {
    Start-ExeInstaller -setupExeFile "$PSScriptRoot\setup.exe" -exeParams "/configure ""$configfile"""
} else { Write-InstallLog "UserOutput: $PkgName is already installed" }

} #endregion // END OF REQUIRED CODE // *****************************************************************************
#region // PUT ANY REQUIRED ADDITIONAL FUNCTIONS BELOW THIS LINE // *************************************************
function Get-InstalledSoftware {
    param(
        [string]$DisplayName,
        [string]$DisplayVersion,
        [string]$arch = "any")

    $(switch -regex ($arch) {
            ".*64.*|any" { "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*" }
            "^((?!64).)*$" { "HKLM:\SOFTWARE\WOw6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*" }
        } ) | Get-ItemProperty | Select-Object DisplayName, DisplayVersion |
    Where-Object { ($_.DisplayName -like "$DisplayName") -and ($_.DisplayVersion -like "$DisplayVersion") }
}

function Start-ExeInstaller {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$setupExeFile,
        [string]$exeParams,
        [int[]]$customExitCodes
    )
        $successExitCodes = @(0, 3010)

        if ($exeParams) {
            $exeParams = [System.Environment]::expandEnvironmentVariables($exeParams)
            Write-InstallLog "UserOutput: Starting: $SetupExeFile $exeParams"
            $exitCode = (Start-Process -FilePath $setupExeFile -ArgumentList $exeParams -PassThru -NoNewWindow -Wait).exitCode
        } else {
            Write-InstallLog "UserOutput: Starting: ""$SetupExeFile"" with no params"
            $exitCode = (Start-Process -FilePath $setupExeFile -PassThru -NoNewWindow -Wait).exitCode
        }

        if ($customExitCodes) { $successExitCodes += $customExitCodes }
        if ($successExitCodes -notcontains $exitCode ) { Write-InstallLog "Installation failed with exit code: $exitCode" -isError }
        else { Write-InstallLog "UserOutput: Installation finished with exit code: $exitCode" }
}

#endregion // END OF ADDITIONAL FUNCTIONS // ************************************************************************
#region // DO NOT EDIT TEXT BELOW // ********************************************************************************
# Logging function
function Write-InstallLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$True, ValueFromPipeline=$True)]
        $Message,
        [switch]$isError
    )
    $ErrorActionPreference ='Continue'
    if ($isError) {
        $Message = $Message.ToUpper()
        "$(Get-Date) ERROR: $Message".Replace("UserOutput:", '') | Out-File $LogFile -Append
        Write-Error $Message}
    else {
        "$(Get-Date): $Message".Replace("UserOutput:", '') | Out-File $LogFile -Append
        Write-Output $Message }
}

$LogFile = "$env:WinDir\Logs\${PkgName}_Script.txt"

Write-InstallLog @"
UserOutput: $('='*32) $(Get-Date) $('='*32) 
START INSTALLATION FOR ${PkgName}:
"@

# Launching main block
Start-ProductInstall -ErrorVariable TotalError

# Error Handling
if (-not $TotalError) { Write-Output "UserOutput:$PkgName setup completed! See $env:WinDir\Logs\${PkgName}_Script.txt for details."}
else { 
    "FOUND ERRORS: ", $TotalError | ForEach-Object { Out-File $LogFile -InputObject $PSItem -Append  }
    throw "$PkgName - Installation Failed! See $env:WinDir\Logs\${PkgName}_Script.txt for details." }

#endregion // NO EDITS // ********************************************************************************************
'@
main