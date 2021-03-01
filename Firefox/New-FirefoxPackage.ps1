function main {
    $url = "https://download.mozilla.org/?product=firefox-latest&os=win64&lang=en-US"
    $url = (Invoke-WebRequest -Uri "$url" -MaximumRedirection 0 -ErrorAction Ignore).Links.Href
    $FileName = ($url.Split('/')[-1]) -replace '%20', ' '
    $AppVersion = ($FileName -replace "[fireoxstup ]", "").TrimEnd(".")
    
    #region create location to download installer
    $ParentDir = "$PsScriptRoot\output"
    if (Test-Path $ParentDir) {}
    else { $null = New-Item $ParentDir -ItemType Directory }
    #endregion create location to download installer

    # download the latest installation
    (New-Object System.Net.WebClient).DownloadFile($url, "$ParentDir\$FileName")
  
    #region create install.ps1 script
    $ScriptTemplate = $ScriptTemplate -replace "<AppVersion>", $AppVersion
    $ScriptTemplate = $ScriptTemplate -replace "<FileName>", $FileName
    $ScriptTemplate | Out-File -FilePath "$PSscriptRoot\output\install.ps1"
    #endregion create install.ps1 script
}

$ScriptTemplate = @'
<#PSScriptInfo
.VERSION
    2.1
.NOTE
    N/A
.PREREQUISITES
    N/A
.EXTERNAL CONFIGURATION ITEMS
    N/A
#>

# Provide Package Name to be used in logging and output
$PkgName = 'Mozilla-Firefox-<AppVersion>'

function Start-ProductInstall {
    [CmdletBinding()]
    param()
#region // PUT REQUIRED CODE FOR INSTALLATION BELOW THIS LINE // ****************************************************
    $ProductName = "Mozilla Firefox <AppVersion> (x64 en-US)"
    $ProductVersion = "<AppVersion>"
    if (-not (Get-InstalledSoftware -DisplayName "$ProductName" -DisplayVersion "$ProductVersion")) {
        Start-ExeInstaller -setupExeFile "$PSScriptRoot\<FileName>" -exeParams "-ms /LOG=""$($env:Windir)\Logs\$($PkgName)_appinstaller.log"""
    } else { Write-InstallLog "UserOutput: $PkgName is already installed" }   

} #endregion // END OF REQUIRED CODE // *****************************************************************************
#region // PUT ANY REQUIRED ADDITIONAL FUNCTIONS BELOW THIS LINE // *************************************************
function Get-InstalledSoftware {
    <#
    .EXAMPLES
       if (Get-InstalledSoftware -DisplayName "7-Zip*" -DisplayVersion "19.0*") { 'DO SOMETHING' }
    #>
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
    <#
    .EXAMPLES
       Start-ExeInstaller -setupExeFile "$PSScriptRoot\npp.7.7.1.Installer.x64.exe" -exeParams "/S"
       Start-ExeInstaller -setupExeFile "$PSScriptRoot\gimp-2.10.12-setup-3.exe" -exeParams "/SP- /VERYSILENT /SUPPRESSMSBOXES /NORESTART /ALLUSERS /LOG=""$($env:Windir)\Logs\$($PkgName)_appinstaller.log"""
    #>
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
    if ($isError) {
        $Message = $Message.ToUpper()
        "$(Get-Date) ERROR: $Message".Replace("UserOutput:", '') | Out-File $LogFile -Append
        throw $Message}
    else {
        "$(Get-Date): $Message".Replace("UserOutput:", '') | Out-File $LogFile -Append
        Write-Output $Message }
}

$LogFile = "$env:WinDir\Logs\${PkgName}_Script.txt"

@"
$('='*32) $(Get-Date) $('='*32) 
START INSTALLATION FOR ${PkgName}:
"@ | Out-File $LogFile -Append

# Launching main block
try {
    Start-ProductInstall
    Write-Output "UserOutput:$PkgName setup completed! See $env:WinDir\Logs\${PkgName}_Script.txt for details." }
catch{
    $msg = "FOUND ERRORS:`n${_}`n"
    Write-Error "$PkgName - Installation Failed!`n$msg See $env:WinDir\Logs\${PkgName}_Script.txt for details." }
#endregion // NO EDITS // ********************************************************************************************
'@

main