function main {
    # Windows 10 build 17063 or newer is requires to extract tar archive
    # horizon update repository
    $url = 'https://softwareupdate.vmware.com/horizon-clients/'
    
    # get url for Windows releases
    $url = "{0}{1}" -f $url, ((Invoke-WebRequest -Uri $url).links | Where-Object innerHTML -like '*windows*').href
    
    # get url for the last version
    $version = ((Invoke-WebRequest -Uri $url).links |
        Sort-Object -property @{
            expression={
                ($_.href -replace"/","") -as [version]
            }
        } | Select-Object -Last 1).href
    $AppVersion = $version.Replace("/", "")
    $url = "{0}{1}" -f $url, $version
    
    # get url for the last build
    $url = "{0}{1}" -f $url, ((Invoke-WebRequest -Uri $url).links |
        Sort-Object -Property href | Select-Object -Last 1).href
    
        # get url for the exe archive
    $FileName = ((Invoke-WebRequest -Uri $url).links | Where-Object innerhtml -like *exe*).href
    $url = "{0}{1}" -f $url, $FileName
    
    #region create location to download installer
    $ParentDir = "$PsScriptRoot\output"
    if (Test-Path $ParentDir) {}
    else { $null = New-Item $ParentDir -ItemType Directory }
    #endregion create location to download installer

    # download the latest installation
    (New-Object System.Net.WebClient).DownloadFile("$url", "$ParentDir\$FileName")

    #region extract sources
    $ExtractTar = Start-Process -FilePath "C:\Windows\System32\tar.exe" -ArgumentList "-xf `"$ParentDir\$FileName`" -C `"$ParentDir`"" -Wait -PassThru -WindowStyle Hidden
    $InstallFile = Get-Item "$ParentDir\*.exe"
    
    # cleanup after file extract
    if ($ExtractTar.exitcode -eq 0) {
        Remove-Item "$ParentDir\$FileName" -Force
        $FileName = $InstallFile.Name
    }
    #endregion extract sources

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
$PkgName = 'VMware-Horizon-Client-<AppVersion>'

function Start-ProductInstall {
    [CmdletBinding()]
    param()
#region // PUT REQUIRED CODE FOR INSTALLATION BELOW THIS LINE // ****************************************************
    $ProductName = "VMware Horizon Client"
    $ProductVersion = "<AppVersion>"
    if (-not (Get-InstalledSoftware -DisplayName "$ProductName" -DisplayVersion "$ProductVersion*")) {
        Start-ExeInstaller -setupExeFile "$PSScriptRoot\<FileName>" -exeParams "/silent /norestart /log ""$($env:Windir)\Logs\$($PkgName)_appinstaller.log"" ADDLOCAL=TSSO INSTALL_SFB=0 INSTALL_HTML5MMR=0 REMOVE=Scanner,FolderRedirection,SerialPort AUTO_UPDATE_ENABLED=0"
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