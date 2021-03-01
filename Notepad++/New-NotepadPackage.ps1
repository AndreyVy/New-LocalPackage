#region download sources
# input parameters
$AppName = "Notepad++ (64-bit x64)"
$url='https://notepad-plus-plus.org/update/getDownloadUrl.php'

#region app specific computing

$urlcontent =  Invoke-WebRequest -Uri $url
[xml]$Appinfo = $urlcontent.Content
$AppVersion = $Appinfo.GUP.Version
$url = $Appinfo.GUP.Location
$FileName = $url.Split("/") | Select-Object -Last 1

#endregion app specific computing

# Create destination
$ParentDir = "$PsScriptRoot\output"
if (Test-Path $ParentDir){}
else {$null = New-Item $ParentDir -ItemType Directory}

# download sources
(New-Object System.Net.WebClient).DownloadFile($url, "$ParentDir\$FileName")
#endregion download sources

#region build install script
$ScriptTemplate = @'
<#PSScriptInfo
.VERSION
    2.1
.NOTE
    -
.PREREQUISITES
    -
.EXTERNAL CONFIGURATION ITEMS
    -
#>

# Provide Package Name to be used in logging and output
$AppName = "<AppName>"
$AppVersion = "<AppVersion>"
$PkgName = "Notepad++-$($AppVersion)-x64"

function Start-ProductInstall {
    [CmdletBinding()]
    param()
#region // PUT REQUIRED CODE FOR INSTALLATION BELOW THIS LINE // ****************************************************
    #Install application
    if (-not (Get-InstalledSoftware -DisplayName "$AppName" -DisplayVersion "$AppVersion")) {
        Start-ExeInstaller -setupExeFile "$PSScriptRoot\<FileName>" -exeParams "/S"
    } else { Write-InstallLog "UserOutput: $PkgName is already installed" }
    #Remove updater
    $removeFileFolder = "C:\Program Files\Notepad++\Updater"
    if (Test-Path $removeFileFolder) {
        Remove-Item -Path $removeFileFolder -Force -Recurse -ErrorAction SilentlyContinue
    }

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
$ScriptTemplate = $ScriptTemplate -replace "<AppName>",  $AppName
$ScriptTemplate = $ScriptTemplate -replace "<AppVersion>", $AppVersion
$ScriptTemplate = $ScriptTemplate -replace "<FileName>", $FileName

$ScriptTemplate | Out-File -FilePath "$PSscriptRoot\output\install.ps1"
#endregion build install script