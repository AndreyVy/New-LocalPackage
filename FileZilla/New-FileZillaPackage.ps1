function main {
    $url = "https://download.filezilla-project.org/client"

    #region create location to download installer
    $ParentDir = "$PsScriptRoot\output"
    if (Test-Path $ParentDir) {}
    else { $null = New-Item $ParentDir -ItemType Directory }
    #endregion create location to download installer

    #region download the latest installation.
    # Expected name pattern is FileZilla_<VERSION>_win64-setup.exe
    # Exclude beta, rc and latest release, which are obsolete
    $VERSION_POSITION = 1
    $FileName = ((Invoke-WebRequest -Uri $url).Links |
    where-object {($_.href -like "*win64-setup.exe*") -and ($_.href -notmatch 'rc|beta|latest')} |
    Sort-Object -Property @{
        expression = {
            ($_.href -split "_")[$VERSION_POSITION] -as [version]
        }
    } | Select-Object -last 1).href
    Invoke-WebRequest -uri "$url/$FileName" -OutFile "$ParentDir\$FileName"
    # DOESN'T WORK: (New-Object System.Net.WebClient).DownloadFile("$url", "$ParentDir\$FileName")
    # RESPONSE: The remote server returned an error: (403) Forbidden.
    #endregion download the latest installation

    # create config file with encoding: UTF-8 with BOM; Unix (LF)
    ( $FzdefaultsXml -replace "`r`n", "`n" ) | Set-Content -Path "$ParentDir\fzdefaults.xml" -NoNewline

    # get product info
    $AppVersion = (Get-Item -Path "$ParentDir\$FileName").VersionInfo.ProductVersion
    
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
    -
.PREREQUISITES
    -
.EXTERNAL CONFIGURATION ITEMS
    Shortcut
#>

# Provide Package Name to be used in logging and output
$PkgName = 'FileZilla-Client-<AppVersion>-x64'

function Start-ProductInstall {
    [CmdletBinding()]
    param()
#region // PUT REQUIRED CODE FOR INSTALLATION BELOW THIS LINE // ****************************************************
    $ProductName = "FileZilla Client <AppVersion>"
    $ProductVersion = "<AppVersion>"
    if (-not (Get-InstalledSoftware -DisplayName "$ProductName" -DisplayVersion "$ProductVersion")) {
        Start-ExeInstaller -setupExeFile "$PSScriptRoot\<FileName>" -exeParams "/S /user=all"
    } else { Write-InstallLog "UserOutput: $PkgName is already installed" }
    
    # The file fzdefaults.xml is used to provide system-wide default settings for FileZilla.
    $copySource = "$PSScriptRoot\fzdefaults.xml" # EXAMPLE: "$PSScriptRoot\*.*"
    $copyDestination = "${env:ProgramFiles}\FileZilla FTP Client\" # EXAMPLE: "${env:ProgramFiles}\DESTINATION\"
    Copy-PackageFile $copySource $copyDestination -ErrorVariable errVar
    if ($errVar) {Write-InstallLog "UserOutput: $PkgName failed to copy files" -isError}
    else {Write-InstallLog "UserOutput: $PkgName files copied"}

    # Suppress "Welcome to FileZilla" dialog
	$xmlFile = "${env:ProgramFiles}\FileZilla FTP Client\fzdefaults.xml"
	if (test-path $xmlFile) {
		$xml = [xml](get-content $xmlFile)		
		if($xml.SelectSingleNode("/FileZilla3/Settings/Setting[@name='Greeting version']") -eq $null){
			$targetNode = $xml.SelectSingleNode("/FileZilla3/Settings")
			$newNode = $targetNode.OwnerDocument.ImportNode(([xml]"<Setting name='Greeting version'></Setting>").selectSingleNode("/Setting"), $true)
			$targetNode.AppendChild($newNode)
		}
		$xml.SelectSingleNode("/FileZilla3/Settings/Setting[@name='Greeting version']").innerText = $ProductVersion		
		$xml.save("$xmlFile")
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

function Copy-PackageFile {
    <#
    .EXAMPLES
        Copy-PackageFile "$PSScriptRoot\*" "${env:ProgramFiles}\Rock Flow Dynamics\" -ErrorVariable errVar
        if ($errVar) {Write-InstallLog "UserOutput: $PkgName failed to copy files" -isError}
        else {Write-InstallLog "UserOutput: $PkgName files copied"}

        Copy-PackageFile "$PSScriptRoot\*.exe" "${env:ProgramFiles}\Rock Flow Dynamics\" -notOverwrite
    #>
    [CmdletBinding()]
    param
    (
        $copySource, 
        $copyDestination, 
        [switch]$notOverwrite
    ) 
    if (Test-Path -Path $copySource) {
        if (-not (Test-Path $copyDestination)) { New-Item $copyDestination -ItemType Directory -Force | Out-Null }

        if ($notOverwrite) { Copy-Item -Path $copySource -Destination $copyDestination -Recurse -Force -Exclude (Get-ChildItem $copyDestination) }
        else { Copy-Item -Path $copySource -Destination $copyDestination -Recurse -Force }
    }
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

$FzdefaultsXml = @'
<?xml version="1.0" encoding="UTF-8" standalone="yes" ?>

<!-- fzdefaults.xml documentation

  The file fzdefaults.xml is used to provide system-wide default settings for
  FileZilla.

  Usage:

    - Windows:

      Put the file fzdefaults.xml into the same directory as filezilla.exe

    - OS X:

      Modify the app bundle, put fzdefaults.xml into the
      Contents/SharedSupport/ subdirectory

    - Other:

      Put fzdefaults.xml into one of the following directories (in order of precedence):

      - ~/.filezilla
      - /etc/filezilla
      - share/filezilla subdirectory of the install prefix.

  Default site manager entries:

    Create some new Site Manager entries and export the list of sites. Rename
    the resulting XML file to fzdefaults.xml or copy the <Servers> block in it
    to fzdefaults.xml. See example below.

  Global configuration settings

    Location of settings directory:

      By default, FileZilla stores its settings in the user's home directory. If
      you want to change this location, modify the "Config Location" setting (see
      below).

      "Config Location" either accepts absolute paths or paths relative to the
      location of fzdefaults.xml
      You can also use environment variables by preceding them with the dollar
      sign, e.g. "$HOME/foo".
      Use $$ to denote a path containing dollar signs, e.g. "c:\$$foobar\" if
      settings should be located in "c:\$foobar".
      A single dot denotes the directory containing fzdefaults.xml

    Kiosk mode

      If the "Kiosk mode" setting is set to 1, FileZilla will not write any
      passwords to disk. If set to 2, FileZilla will not write to any
      configuration file. The latter is useful if FileZilla gets executed from
      read-only media.

    Disable update check

      If the "Disable update check" setting is set to 1, the capability to
      check for new FileZilla versions will be completely disabled.

    Cache directory

      Use the "Cache directory" setting to override where FileZilla places
      its resource cache. Same rules for environment variables and relative
      paths as for the "Config Location" setting apply.
        
-->

<FileZilla3>
  <Settings>
    <Setting name="Greeting version"></Setting>
    <Setting name="Disable update check">1</Setting>
  </Settings>
</FileZilla3>
'@
main