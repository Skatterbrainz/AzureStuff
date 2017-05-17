
function Initialize-AzureResourceGroup {
    [CmdletBinding(SupportsShouldProcess=$True)]
    param (
        [parameter(Mandatory=$True, HelpMessage="Resource Group name")]
            [ValidateNotNullOrEmpty()]
            [string] $Name, 
        [parameter(Mandatory=$True, HelpMessage="Location name or code")]
            [ValidateNotNullOrEmpty()]
            [string] $Location
    )
    $rgx = Get-AzureRmResourceGroup -Name $Name -Location $Location -ErrorAction SilentlyContinue
    if ($rgx -eq $null) {
        Write-Verbose "info: creating resource group: $Name..."
        if (-not $TestMode) {
            $rgx = New-AzureRmResourceGroup -Name $Name -Location $Location -ErrorAction SilentlyContinue
        }
    }
    else {
        Write-Verbose "info: resource group already exists: $Name"
    }
    Write-Output $rgx
}
