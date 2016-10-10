param (
    [parameter(Mandatory=$False)] [string] $azRgName = "rg1",
    [parameter(Mandatory=$False)] [string] $azVmList = "VM01,VM02",
    [parameter(Mandatory=$False)] [string] $azEnv   = "AzureCloud",
    [parameter(Mandatory=$False)] [string] $azAcct  = "ds0934@hotmail.com",
    [parameter(Mandatory=$False)] [string] $azTenId = "03b55dea-ce59-4531-b1ef-a590e7dbd162",
    [parameter(Mandatory=$False)] [string] $azSubId = "af15d920-86d8-4062-8801-d11eee853114"
)

# establish session authentication

if ($azCred -eq $null) {
    $azCred = Login-AzureRmAccount -EnvironmentName $azEnv -AccountId $azAcct -SubscriptionId $azSubId -TenantId $azTenId
}

try {
    Write-Output "Querying resource group $azRgName..."
    $rgx = Get-AzureRmResourceGroup -Name $azRgName
    $go = $true
    $rgLoc = $rgx.Location
}
catch {
    Write-Error "uh oh?  Resource Group has gone bye bye?"
}

if ($go -eq $true) {
    
    Write-Output "Resource Group $azRgName is in $rgLoc"
    
    foreach ($vm in $azVmList.Split(",")) {
        
        $azVM     = Get-AzureRmVm -ResourceGroupName $azRgName -Name $vm
        $azVmStat = Get-AzureRmVm -ResourceGroupName $azRgName -Name $vm -Status
        $azVmLoc  = $azVM.Location
        $azVmType = $azVM.HardwareProfile.VmSize
        $azVmOs   = $azVM.StorageProfile.ImageReference.Sku
        $azVmAdmUser = $azVM.OSProfile.AdminUsername

        Write-Output "$vm :: Location: $azVmLoc / Size: $azVmType / OS: $azVmOs"

        foreach ($vmSC in $azVmStat.Statuses) {
            if ($vmSC.DisplayStatus -eq "VM running") {
                Write-Output "`t$vm is currently RUNNING."
                #Write-Output "`tStopping $vm..."
                #Stop-AzureRmVm -Name $vm -ResourceGroupName $azRgName -Force
            }
            elseif ($vmSC.DisplayStatus -eq "VM deallocated") {
                Write-Output "`t$vm is currently STOPPED."
                #Write-Output "`tStarting $vm..."
                #Start-AzureRmVm -Name $vm -ResourceGroupName $azRgName
            }
        }
    }
}

#$vmNew = New-AzureRmVMConfig -VMName "VM3" -VMSize "Standard_D2"

#Get-AzureRmVM -ResourceGroupName $azRgName -Name "VM1"
