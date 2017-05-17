#requires -modules AzureRM
#requires -version 3

function Save-AzureLogin {
    param (
        [parameter(Mandatory=$True, HelpMessage="Name of profile")]
        [ValidateNotNullOrEmpty()]
        [string] $ProfileName
    )
    Login-AzureRmAccount
    Save-AzureRmProfile -Path .\$ProfileName.json -Force
    Select-AzureRmProfile -Path .\$ProfileName.json
}
