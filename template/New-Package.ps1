function main{
    #region preparation for media download
    $AppName = "Google Chrome"
    $url='https://dl.google.com/dl/chrome/install/GoogleChromeStandaloneEnterprise64.msi'
    $FileName = $url.Split("/") | Select-Object -Last 1
    #endregion preparation for media download
    
    #region download media
    $NewSource = get-sourcefile -url $url -FileName $FileName
    #endregion download media
    
    #region preparation for install script build
    [string]$Comment = get-msisummaryinfo -msifilepath $NewSource.FullName
    $AppVersion = $Comment.Trim() -split " " | Select-Object -First 1
    #endregion preparation for install script build

    new-installscript -ScriptTemplate $ScriptTemplate -AppName $AppName -AppVersion $AppVersion -FileName $NewSource.Name
}

#region declaration addition functions which are called in main()
function get-sourcefile {
    param(
        [Parameter(Mandatory)] [String] $url,
        [Parameter(Mandatory)] [String] $FileName
    )
    $ParentDir = "$PsScriptRoot\output"
    if (Test-Path $ParentDir){}
    else {$null = New-Item $ParentDir -ItemType Directory}
    
    # download sources
    (New-Object System.Net.WebClient).DownloadFile($url, "$ParentDir\$FileName")
    Get-Item "$ParentDir\$FileName"
}

function new-installscript {
    param(
        [Parameter(Mandatory)]    
        [string] $ScriptTemplate,
        [Parameter(Mandatory)]  
        [string] $AppName,
        [Parameter(Mandatory)]  
        [string] $AppVersion,
        [Parameter(Mandatory)]  
        [string] $FileName
    )
    
    $ScriptTemplate = $ScriptTemplate -replace "<AppName>",  $AppName
    $ScriptTemplate = $ScriptTemplate -replace "<AppVersion>", $AppVersion
    $ScriptTemplate = $ScriptTemplate -replace "<FileName>", $FileName

    $ScriptTemplate | Out-File -FilePath "$PSscriptRoot\output\install.ps1"
}

function get-msisummaryinfo {
    param (
        [Parameter(Mandatory)] [String] $msifilepath
    )
    $READONLY = 0
    $COMMENTS = 6
    $msidb = (New-Object -ComObject WindowsInstaller.Installer ).OpenDatabase("$msifilepath", $READONLY)
    $SummaryInfo = $msidb.SummaryInformation(4)

    $Comment = $SummaryInfo.Property($COMMENTS)
    $SummaryInfo.Persist
    $msidb.Close
    $Comment

}
#endregion declaration addition functions which are called in main()

#region declaration script template variable as here-string
$ScriptTemplate = @'
<#PSScriptInfo
.VERSION
    2.1
.NOTE
    -
.PREREQUISITES
    -
.EXTERNAL CONFIGURATION ITEMS
    GPO
#>

$ProductName = "<AppName>"
$ProductVersion = "<AppVersion>"
$PkgName = "${ProductName}_${ProductVersion}_x64"

function Start-ProductInstall {
    [CmdletBinding()]
    param()
    if (-not (Get-InstalledSoftware -DisplayName "$ProductName" -DisplayVersion "$ProductVersion")) {
        Start-WindowsInstaller -MSIFile "$PSScriptRoot\<FileName>" -InstallParams "ADDLOCAL=ALL ALLUSERS=1 REBOOT=ReallySuppress /qn /L*v `"$env:Windir\Logs\$($PkgName)_appinstaller.log`""
    } else { Write-InstallLog "UserOutput: $PkgName is already installed" }
    
    Write-Output "UserOutput: Disable ActiveSetup entry to fix Shortcut problems on RDS"
    if (!((get-itemProperty "HKLM:\SOFTWARE\Microsoft\Active Setup\Installed Components\{8A69D345-D564-463c-AFF1-A69D9E530F96}").'StubPath' -eq $null)){
        Remove-ItemProperty -path "HKLM:\SOFTWARE\Microsoft\Active Setup\Installed Components\{8A69D345-D564-463c-AFF1-A69D9E530F96}" -name "StubPath"
    }

    Write-Output "UserOutput: Disable Google Update services"
    $Services = Get-Service | Where-Object {$_.DisplayName -like '*google*'}
    foreach($service in $Services)
    {
        Stop-Service $service -ErrorAction SilentlyContinue
        Set-Service -Name $service.name -StartupType Disabled
    }

    Write-Output "UserOutput: Remove Google Update scheduled tasks"
    Get-ScheduledTask *google* | Unregister-ScheduledTask -Confirm:$false
}

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

function Start-WindowsInstaller {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$True)]
        [string]$MSIFile,
        [string]$InstallParams = ""
    )
    $commandLine = "/i `"$MSIFile`" $InstallParams"
    Write-InstallLog "UserOutput: Starting: msiexec $commandLine"
    $exitCode = (Start-Process -FilePath 'msiexec.exe' -ArgumentList $commandLine -Wait -PassThru).ExitCode
    if ((0,3010) -notcontains $exitCode ) {
        Write-InstallLog "Installation failed with exit code: $exitCode" -isError
    } else {
        Write-InstallLog "UserOutput: Installation finished with exit code: $exitCode"
    }
}

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
'@

#endregion declaration script template variable as here-string

#region start script execution
main
#endregion start script execution