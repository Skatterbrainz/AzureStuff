param (
    [parameter(Mandatory=$False)] [string] $azEnv      = "AzureCloud",
    [parameter(Mandatory=$False)] [string] $azAcct     = "<<YOUR_ID>>",
    [parameter(Mandatory=$False)] [string] $azTenId    = "<<YOUR_TENANT_ID>>",
    [parameter(Mandatory=$False)] [string] $azSubId    = "<<YOUR_SUBSCRIPTION_ID>>",
    [parameter(Mandatory=$False)] [string] $WorkspaceName   = "dsOms1",
	[parameter(Mandatory=$False)] [string] $VMResourceGroup = "rg001",
    [parameter(Mandatory=$False)] [string] $VMResourceName  = "",
    [parameter(Mandatory=$False)] [string] $subnetName = "dssubnet1",
    [parameter(Mandatory=$False)] [string] $vnetName   = "vnetds1"
)

if ($azCred -eq $null) {
    Write-Output "authentication is required."
    $azCred = Login-AzureRmAccount -EnvironmentName $azEnv -AccountId $azAcct -SubscriptionId $azSubId -TenantId $azTenId
}
else {
    Write-Output "authentication already confirmed."
}

Select-AzureSubscription -SubscriptionId "**"

$workspace = (Get-AzureRmOperationalInsightsWorkspace).Where({$_.Name -eq $WorkspaceName})

if ($workspace.Name -ne $WorkspaceName)
{
    Write-Error "Unable to find OMS Workspace $workspaceName. Do you need to run Select-AzureRMSubscription?"
}

$workspaceId = $workspace.CustomerId
$workspaceKey = (Get-AzureRmOperationalInsightsWorkspaceSharedKeys -ResourceGroupName $workspace.ResourceGroupName -Name $workspace.Name).PrimarySharedKey

$vm = Get-AzureRMVM -ResourceGroupName $VMresourcegroup -Name $VMresourcename
$location = $vm.Location

# For Windows VM uncomment the following line
Set-AzureRMVMExtension -ResourceGroupName $VMresourcegroup -VMName $VMresourcename -Name 'MicrosoftMonitoringAgent' -Publisher 'Microsoft.EnterpriseCloud.Monitoring' -ExtensionType 'MicrosoftMonitoringAgent' -TypeHandlerVersion '1.0' -Location $location -SettingString "{'workspaceId':  '$workspaceId'}" -ProtectedSettingString "{'workspaceKey': '$workspaceKey' }"

# For Linux VM uncomment the following line
# Set-AzureRMVMExtension -ResourceGroupName $VMresourcegroup -VMName $VMresourcename -Name 'OmsAgentForLinux' -Publisher 'Microsoft.EnterpriseCloud.Monitoring' -ExtensionType 'OmsAgentForLinux' -TypeHandlerVersion '1.0' -Location $location -SettingString "{'workspaceId':  '$workspaceId'}" -ProtectedSettingString "{'workspaceKey': '$workspaceKey' }"
