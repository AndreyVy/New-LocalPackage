#region download sources
# input parameters
$url='https://www.7-zip.org/'

#region app specific computing

$zipweb = Invoke-WebRequest -Uri "$url/download.html"
# url links are stored in a sequence they disaplyed in the web-page. It is acceptable to assume
# that first link that mutch patter x64 and msi is desired link
$url = "$url/{0}" -f ($zipweb.links | Where-Object href -like "*x64*msi*" | Select-Object -First 1).href
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
function Get-MSIProperty {
    <# 
    .SYNOPSIS 
    This function retrieves properties from a Windows Installer MSI database. 
    .DESCRIPTION 
    This function uses the WindowInstaller COM object to pull all values from the Property table from a MSI 
    .EXAMPLE 
    Get-MsiDatabaseProperties 'MSI_PATH' 
    .PARAMETER FilePath 
    The path to the MSI you'd like to query 
    #> 
    [CmdletBinding()] 
    param ( 
        [Parameter(Mandatory = $True, 
            ValueFromPipeline = $True, 
            ValueFromPipelineByPropertyName = $True, 
            HelpMessage = 'What is the path of the MSI you would like to query?')] 
        [IO.FileInfo[]]$FilePath 
    ) 
 
    begin { 
        $com_object = New-Object -com WindowsInstaller.Installer 
    } 
 
    process { 
        try { 
 
            $database = $com_object.GetType().InvokeMember( 
                "OpenDatabase", 
                "InvokeMethod", 
                $Null, 
                $com_object, 
                @($FilePath.FullName, 0) 
            ) 
 
            $query = "SELECT * FROM Property" 
            $View = $database.GetType().InvokeMember( 
                "OpenView", 
                "InvokeMethod", 
                $Null, 
                $database, 
                ($query) 
            ) 
 
            $View.GetType().InvokeMember("Execute", "InvokeMethod", $Null, $View, $Null) 
 
            $record = $View.GetType().InvokeMember( 
                "Fetch", 
                "InvokeMethod", 
                $Null, 
                $View, 
                $Null 
            ) 
 
            $msi_props = @{ } 
            while ($null -ne $record) { 
                $prop_name = $record.GetType().InvokeMember("StringData", "GetProperty", $Null, $record, 1) 
                $prop_value = $record.GetType().InvokeMember("StringData", "GetProperty", $Null, $record, 2) 
                $msi_props[$prop_name] = $prop_value 
                $record = $View.GetType().InvokeMember( 
                    "Fetch", 
                    "InvokeMethod", 
                    $Null, 
                    $View, 
                    $Null 
                ) 
            } 
 
            New-Object -TypeName PSObject -Property $msi_props
 
        }
        catch { 
            throw "Failed to get MSI file version the error was: {0}." -f $_ 
        } 
    } 
}
$AppInfo = Get-MSIProperty "$ParentDir\$FileName" | Select-Object  ProductName, ProductVersion
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
$ProductName = "<AppName>"
$ProductVersion = "<AppVersion>"
$PkgName = "$ProductName_$ProductVersion"

function Start-ProductInstall {
    [CmdletBinding()]
    param()
#region // PUT REQUIRED CODE FOR INSTALLATION BELOW THIS LINE // ****************************************************

    if (-not (Get-InstalledSoftware -DisplayName "$ProductName" -DisplayVersion "$ProductVersion")) {
        Start-WindowsInstaller -MSIFile "$PSScriptRoot\<FileName>" -InstallParams "ADDLOCAL=ALL ALLUSERS=1 REBOOT=ReallySuppress /qn /L*v `"$env:Windir\Logs\$($PkgName)_appinstaller.log`""
    } else { Write-InstallLog "UserOutput: $PkgName is already installed" }
    


} #endregion // END OF REQUIRED CODE // *****************************************************************************
#region // PUT ANY REQUIRED ADDITIONAL FUNCTIONS BELOW THIS LINE // *************************************************
function Start-WindowsInstaller {
    <#
    .EXAMPLES
    Start-WindowsInstaller -MSIFile "$PSSCriptRoot\7z1900-x64.msi" -InstallParams "ADDLOCAL=ALL ALLUSERS=1 REBOOT=ReallySuppress  /qn /L*v `"$env:Windir\Logs\$($PkgName)_appinstaller.log`""
    Start-WindowsInstaller -MSIFile "$PSSCriptRoot\7z1900-x64.msi" -InstallParams "ADDLOCAL=ALL TRANSFORMS=`"$PSSCriptRoot\7zip.mst`" ALLUSERS=1 REBOOT=ReallySuppress  /qn /L*v `"$env:Windir\Logs\$($PkgName)_appinstaller.log`""
    #>
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
$ScriptTemplate = $ScriptTemplate -replace "<AppName>",  $AppInfo.ProductName
$ScriptTemplate = $ScriptTemplate -replace "<AppVersion>", $AppInfo.ProductVersion
$ScriptTemplate = $ScriptTemplate -replace "<FileName>", $FileName

$ScriptTemplate | Out-File -FilePath "$PSscriptRoot\output\install.ps1"
#endregion build install script