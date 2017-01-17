<#
.DESCRIPTION
Import AD user accounts from a CSV input file. Accommodates custom
and extended attributes if requested.

.PARAMETER CsvFile
Required: Full path and filename of CSV input file.

Note that the CSV input file must have the following...

1. The top row contains AD schema attribute names
2. One of the headings is "path" for the LDAP path where accounts will be created
3. No read-only attributes are specified (e.g. msExtendedAttribute20)

.EXAMPLE
.\Import-AdUsers.ps1 -CsvFile "users.csv" -Verbose

.NOTES
Author = David Stein
Date Created = 01/02/2017
Date Updated = 01/17/2017

USE AT YOUR OWN RISK - NO WARRANTY PROVIDED
User accepts any and all risk and liability 
#>

param (
    [parameter(Mandatory=$True, Position=0)]
    [ValidateNotNullOrEmpty()]
    [string] $CsvFile
)
$ErrorActionPreference = "Stop"
$startTime = Get-Date

function New-RandomPassword {
    [CmdletBinding(DefaultParameterSetName='Length')]
    param (
        [parameter(Mandatory=$False)][int] $Length = 15
    )
    <#
    .DESCRIPTION
    Generate a random password of a given length.
   
    .PARAMETER Length
    Optional: Length of password to generate (number of digits).
    Default: 15

    .EXAMPLE
    New-RandomPassword -Length 24
	
	thanks to http://blog.oddbit.com/2012/11/04/powershell-random-passwords/
    #>

    $punc   = 46..46
    $digits = 48..57
    $letters = 65..90 + 97..122
    $password = Get-Random -count $length `
        -Input ($punc + $digits + $letters) |
            % -Begin { $aa = $null } `
            -Process {$aa += [char]$_} `
            -End {$aa}
    return $password
}

function Update-ADUser {
    [CmdletBinding(DefaultParameterSetName='User')]
    param (
        [parameter(
            Position=0, 
            Mandatory=$True, 
            ValueFromPipeline=$True)
        ] 
        [Microsoft.ActiveDirectory.Management.ADUser]
        $User, 
        [parameter(
            Position=1, 
            Mandatory=$True)
        ]
        [PSCustomObject[]]
        $DataRow, 
        [parameter(
            Position=2, 
            Mandatory=$True)
        ]
        [string] $AttList
    )
    <#
    .DESCRIPTION
    Applies an array of attribute values to a specified AD user object.
    
    .PARAMETER User
    An object defined from Get-ADUser.
    
    .PARAMETER DataRow
    An array obtained from one row in a CSV input file.
    
    .PARAMETER AttList
    A comma-delimited string that contains the names of AD user schema attributes to apply.

    .EXAMPLE
    Update-ADUser -User $user -DataRow $csvRow -AttList $atts
    #>

    foreach ($att in $AttList.Split(',')) {
        write-verbose "internal: att = $att"
        if (!($excluded.Contains($att))) {
            $v = $DataRow."$att"
            write-verbose "internal: value = $v"
            if ($($v.Trim()).Length -gt 0) {
                write-verbose "info: applying input: $att"
                write-verbose "info: value = $v"
                Set-ADUser $User -replace @{"$att"="$v"} -Confirm:$False
            }
            else {
                write-verbose "info: ignoring null input: $att"
            }
        }
    }
}

if (!(Test-Path $csvfile)) {
    write-host "error: $csvfile not found"
}
else {
    $rowcount = 0
    $excluded = ("name","path","samaccountname")
    write-verbose "info: reading input data file..."
    $csvData = Import-Csv -Path $csvfile
    foreach ($row in $csvData) {
        $upath = $row.Path
        $rpwd  = New-RandomPassword -Length 24
        $sam = $row.sAMSccountName -replace "(?s)^.*\\", ""
        try {
            $user = Get-ADUser -Identity "$sam" -ErrorAction SilentlyContinue
            write-output "info: updating user: $sam"
        }
        catch {
            $user = $null
            write-output "info: creating user: $sam"
            New-ADUser -Name "$sam" -SamAccountName "$sam" -Path $upath -AccountPassword (ConvertTo-SecureString $rpwd -AsPlainText -Force) -Enabled:$True
            $user = Get-ADUser -Identity "$sam"
        }            
        if ($user -eq $null) {
            break
        }
        $atts1  = "employeeid,displayName,title,telephoneNumber,mobile,"
        $atts1 += "physicalDeliveryOfficeName,mail,initials,Description,"
        $atts1 += "company,facsimileTelephoneNumber,department,co,l,manager,"
        $atts1 += "st,streetAddress,postalCode,sn,givenName,userPrincipalName,"
        $atts1 += "employeeType,pager,MailNickName,roomNumber,businessCategory,"
        $atts1 += "departmentnumber,otherTelephone,street,adminDescription,"
        $atts1 += "countryCode,initials,ipPhone,localeID,c,proxyaddresses"

        Update-ADUser $user $row $atts1

        write-verbose "info: exchange attributes..."

        $atts3  = "destinationIndicator,ExtensionAttribute1,ExtensionAttribute3,"
        $atts3 += "extensionattribute5,extensionattribute6,extensionattribute8,"
        $atts3 += "extensionattribute12,ExtensionName"
        
        Update-ADUser $user $row $atts3

        write-verbose "info: custom attributes..."

        $atts4  = "mlisprimary,mlacctcd,mlsublob,mlDvision,mlsubdivision,msRTCSIP-PrimaryUserAddress,"
        $atts4 += "mlSubDivDescr,mlSection,mlSectionDescr,mlsubSection,mlsubSectionDescr"

        #Update-ADUser $user $row $atts4

        $rowcount += 1
    }
    write-host "info: completed $rowcount rows"
}
$StopTime = Get-Date
$RunTime= New-TimeSpan -Start $startTime -End $StopTime
write-host "info: runtime was $($RunTime.Seconds) seconds"
