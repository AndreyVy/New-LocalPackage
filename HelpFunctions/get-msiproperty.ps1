param ( [Parameter(Mandatory)] [String] $msifilepath )

# open msi in read only mode
$READONLY = 0
$msidb = (New-Object -ComObject WindowsInstaller.Installer ).OpenDatabase("$msifilepath", $READONLY)

# read property table
$queryString = 'SELECT * FROM `Property`'
$PropertyTable = $msidb.OpenView($queryString)
$PropertyTable.Execute()

# read each property name and value row-by-row
$PROP_NAME_ID = 1
$PROP_VALUE_ID = 2
$Props = @{ }
do {
    $Property = $PropertyTable.Fetch()
    If ($null -eq $Property) { break }
    $PropName = $Property.StringData($PROP_NAME_ID)
    $PropVal = $Property.StringData($PROP_VALUE_ID)
    $Props[$PropName] = $PropVal
} while ($true)

$PropertyTable.Close
$msidb.Close

# return result as ps object
New-Object -TypeName PSObject -Property $Props
