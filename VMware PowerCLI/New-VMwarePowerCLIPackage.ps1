function main {
    #region check and install dependencies
    $PackageProvider = @{'Name' = 'NuGet'; 'Version' = [version]'2.8.5.201'}
    $NugetIsPresent = Get-PackageProvider -ListAvailable |
    Where-Object {( $_.Name -eq $PackageProvider.Name ) -and ( $_.Version -ge $PackageProvider.Version )}
    if (-not ($NugetIsPresent)) { $null = Install-PackageProvider -Name $PackageProvider.Name -MinimumVersion $PackageProvider.Version -Force}
    #endregion check and install dependencies

    #region create location to download installer
    $ParentDir = "$PsScriptRoot\output\"
    if (Test-Path $ParentDir) {}
    else { $null = New-Item $ParentDir -ItemType Directory }
    #endregion create location to download installer

    #region download media
    find-module -Name VMware.PowerCLI -Repository 'PSGallery' -OutVariable PowerCliInfo | Save-Module -Path $ParentDir
    #endregion download media

    #region create install.ps1 script
    $ScriptTemplate = $ScriptTemplate -replace "<AppVersion>", $PowerCliInfo.Version
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
$PkgName = 'VMWare-PowerCli-<AppVersion>'

function Start-ProductInstall {
    [CmdletBinding()]
    param()
#region // PUT REQUIRED CODE FOR INSTALLATION BELOW THIS LINE // ****************************************************

    Copy-Item -Path "$PSScriptRoot\*" -Destination 'C:\Program Files\WindowsPowerShell\Modules' -Recurse -Exclude 'install.ps1' -Force

} #endregion // END OF REQUIRED CODE // *****************************************************************************
#region // PUT ANY REQUIRED ADDITIONAL FUNCTIONS BELOW THIS LINE // *************************************************



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