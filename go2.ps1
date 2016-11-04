
param (
    [parameter(Mandatory=$False)] [string] $azEnv      = "AzureCloud",
    [parameter(Mandatory=$False)] [string] $azAcct     = "kevin@thenext.net",
    [parameter(Mandatory=$False)] [string] $azTenId    = "ffefc0c4-2ef8-49f8-a251-907971968a26",
    [parameter(Mandatory=$False)] [string] $azSubId    = "d2fc1b6f-162c-4553-b423-6c8b9902819e",
    [parameter(Mandatory=$False)] [string] $InputFile  = "go.csv"
)

Write-Output "checking if session is authenticated..."
if ($azCred -eq $null) {
    Write-Output "authentication is required."
    $azCred = Login-AzureRmAccount -SubscriptionId $azSubId -TenantId $azTenId
}
else {
    Write-Output "authentication already confirmed."
}

Write-Output "reading input file: $InputFile..."
$csvData = Import-Csv $InputFile

if ($csvData -ne $null) {

    foreach ($row in $csvData) {
        $Location       = $row.Location
		$vmName         = $row.Name
        $sourceCont     = $row.sourceContainer
        $sourceVHD      = $row.SourceVHD
        $destCont       = $row.destinationContainer
		$osDiskUri      = $row.osdiskUri
		$saName         = $row.StorageAccount
        $storagesku     = $row.StorageSku
        $vmSize         = $row.Size
        $Publisher      = $row.PublisherName
        $Offer          = $row.Offer
        $Version        = $row.Version
        $Skus           = $row.Skus
        $privIP         = $row.PrivateIP
        $vnetName       = $row.vnetName
        $subnetName     = $row.SubnetName
        $subnetPfx      = $row.SubnetRange
        $addressPfx     = $row.AddressRange
        $rgName         = $row.ResourceGroup
        $rgstore        = $row.StorageResGroup
        $rgnet          = $row.NetworkingResGroup
        $caching        = $row.caching
        $DataDiskSize1  = $row.DataDiskSize1
        $nicName        = "$vmName"+"nic1"
        $osdiskname     = "$vmName"+"os.vhd"
        $diskName       = "$vmName"+"osdisk"
        $datadiskname   = "$vmName"+"datadisk.vhd"
        $ipName         = "$vmName"+"pip1"

        if ($vmName.Substring(0,1) -ne ";") {
            # Check Storage Account Availability
            $StorageAccountNameExists   = (Get-AzureRmStorageAccountNameAvailability -Name $saName).NameAvailable
            $StNameExistsInTheTenant    = (Get-AzureRmStorageAccount | ?{$_.StorageAccountName -eq "$saName"})
            $StNameExistsInTheTenantB   = [bool]$StNameExistsInTheTenant
            $StorageAccountNameExistsB  = [bool]$StorageAccountNameExists
            if ((!($StorageAccountNameExistsB)) -and (!($StNameExistsInTheTenantB))){
                Write-Output "Storage account" $saName "name already taken"
                Write-Output "Please choose another Storage Account Name"
                Write-Output "This Powershell command can be used: Get-AzureRmStorageAccountNameAvailability -Name"
                Break
            }
            else {
                Write-Output "Storage account: $saName is either available or already yours"
            }
            # Verify .vhd is in place if specified in .csv
            $stAcct             = (Get-AzureRmStorageAccount | ?{$_.StorageAccountName -eq "$saName"})
            $stURI              = $stAcct.PrimaryEndpoints.Blob.ToString()
            $StorageContext     = (Get-AzureRmStorageAccount -ResourceGroupName $rgstore -Name $saName).context
            $CheckForSourceVHD  = Get-AzureStorageBlob -Context $StorageContext -Container $sourceCont | ? {$_.name -eq $sourceVHD}
            $CheckForSourceVHDB = [bool]$CheckForSourceVHD
            if (($imageUri -ne "") -and ($Publisher -eq "") -and (!($CheckForSourceVHDB))){
                Write-Output "Source image not found (.vhd): $sourceVHD"
                Break
            }    
            else {
                Write-Output "Source image found or this is a Marketplace build"
            }
        
            # Resource Group
            $rg = Get-AzureRmResourceGroup -Name $rgName -Location $Location -ErrorAction SilentlyContinue
            if ($rg -eq $null) {
                Write-Output "creating resource group: $rgName..."
                $rg = New-AzureRmResourceGroup -Name $rgName -Location $Location
            }
            else {
                Write-Output "resource group already exists: $rgName"
            }
            
            # Resource Group Storage
            $rgs = Get-AzureRmResourceGroup -Name $rgstore -Location $Location -ErrorAction SilentlyContinue
            if ($rgs -eq $null) {
                Write-Output "creating resource group: $rgstore..."
                $rgs = New-AzureRmResourceGroup -Name $rgstore -Location $Location
            }
            else {
                Write-Output "resource group already exists: $rgstore"
            }
            
            # Resource Group Network
            $rgn = Get-AzureRmResourceGroup -Name $rgnet -Location $Location -ErrorAction SilentlyContinue
            if ($rgn -eq $null) {
                Write-Output "creating resource group: $rgnet..."
                $rgn = New-AzureRmResourceGroup -Name $rgnet -Location $Location
            }
            else {
                Write-Output "resource group already exists: $rgnet"
            }
            
            # Storage Account
            $stAcct = (Get-AzureRmStorageAccount | ?{$_.StorageAccountName -eq "$saName"})
            if ($stAcct -eq $null) {
                Write-Output "creating storage account: $saName..."
                $stAcct = New-AzureRmStorageAccount -ResourceGroupName $rgstore -Name $saName -SkuName $storagesku -Kind Storage -Location $Location #-ErrorAction SilentlyContinue
            }
            else {
                Write-Output "storage account already exists: $saName"
            }
            if ($stAcct -ne $null) {
                $stURI = $stAcct.PrimaryEndpoints.Blob.ToString()
                Write-Output "storage account URI: $stURI"
            }
            
            # Subnet
            if ((Get-AzureRmVirtualNetwork).Subnets | ?{$_.Name -eq "$subnetName"}){
                Write-Output "subnet already exists: $subnetName"
                $subnet = ((Get-AzureRmVirtualNetwork).Subnets | ?{$_.Name -eq "$subnetName"}).Id
            } 
            else {
                Write-Output "creating virtual network subnet: $subnetName / $subnetPfx..."
                $subnet = New-AzureRmVirtualNetworkSubnetConfig -Name $subnetName -AddressPrefix $subnetPfx
            }
            
            # VNet
            $vnet = (Get-AzureRmVirtualNetwork | ?{$_.Name -eq "$vnetName"})
            if ($vnet -ne $null) {
                Write-Output "virtual network already exists: $vnetName"
            }
            else {
                Write-Output "creating virtual network: $vnetName in $Location..."
                $vnet = New-AzureRmVirtualNetwork -Name $vnetName -ResourceGroupName $rgnet -Location $Location -AddressPrefix $addressPfx -Subnet $subnet
            }
            
            # Public IP Address Creation
            Write-Output "creating public IP: $ipName..."
            $pip = New-AzureRmPublicIpAddress -Name $ipName -ResourceGroupName $rgName -Location $Location -AllocationMethod Static
            
            # NIC Creation
            Write-Output "creating NIC: $nicName..."
            $nic = New-AzureRmNetworkInterface -Name $nicName -ResourceGroupName $rgName -Location $Location -SubnetId $subnet -PublicIpAddressId $pip.Id -PrivateIpAddress $privIP
            
            # VM components
            Write-Output "preparing components for virtual machine..."
            $SecurePassword = ConvertTo-SecureString "PickaPassword!2830" -AsPlainText -Force
            $Credential = New-Object System.Management.Automation.PSCredential ("install", $SecurePassword); 
            $vm = New-AzureRmVMConfig -VMName $vmName -VMSize $vmSize
            $vm = Set-AzureRmVMOperatingSystem -VM $vm -Windows -ComputerName $vmname -Credential $Credential -ProvisionVMAgent -EnableAutoUpdate
            $vm = Add-AzureRmVMNetworkInterface -VM $vm -Id $nic.Id
            
            # VM Disk (OS)
            $osDiskUri   = "$stURI"+"$destCont"+"/$osdiskname"
            if ($Publisher -eq "") { 
                $imageUri    = "$stURI"+"$sourceCont"+"/$sourceVHD"
                Write-Output "disk blob uri is $osDiskUri"
                Write-Output "Image from Source VHD $osDiskUri"
                $vm = Set-AzureRmVMOSDisk -VM $vm -Name $diskName -VhdUri $osDiskUri -CreateOption FromImage -SourceImageUri $imageUri -Windows
            }
            else {
                Write-Output "disk blob uri is $osDiskUri"
                Write-Output "Marketplace Image from publisher $Publisher"
                $vm = Set-AzureRmVMOSDisk -VM $vm -Name $diskName -VhdUri $osDiskUri -CreateOption FromImage
                $vm = Set-AzureRmVMSourceImage -VM $vm -PublisherName $Publisher -Offer $Offer -Skus $Skus -Version $Version
            }
            
            # VM Creation
            Write-Output "creating virtual machine: $vmName..."
            New-AzureRmVM -ResourceGroupName $rgName -Location $Location -VM $vm
            
            # VM Disk (DATA)            
            if ($DataDiskSize1 -ne "") {
                $dataDiskUri = "$stURI"+"$destCont"+"/$datadiskname"
                Write-Output "Creating Data Disk: $datadiskname"     
                $vm = Get-AzureRmVM -ResourceGroupName $rgName -Name $vmName 
                Add-AzureRmVMDataDisk -VM $vm -Name $datadiskname -VhdUri $dataDiskUri -Caching $Caching -DiskSizeinGB $DataDiskSize1  -CreateOption Empty
                Update-AzureRmVM -ResourceGroupName $rgName -VM $vm
            }
            else {
                Write-Output "No Data Disk Requested"
            }
            
            # Write Results to Screen
            $vmNic = Get-AzureRmNetworkInterface -Name $nicName -ResourceGroupName $rgName
            $pvtIP = $($vmNic.IpConfigurations).PrivateIpAddress
            $pubIP = $(Get-AzureRmPublicIpAddress -Name $ipName -ResourceGroupName $rgname).IpAddress
            Write-Output "`tPrivate IP: $pvtIP"
            Write-Output "`tPublic IP: $pubIP"
        }
        
<#        else {
            Write-Output "testmode enabled."
            Write-Output "vm: $vmName / size: $vmSize / Location: $Location"
            $blobPath  = "$vmName"+"os.vhd"
            $osDiskUri = "$stURI"+"vhds/$blobPath"
            $diskName  = "$vmName"+"osdisk"
            Write-Output "`tstorage blob: $osDiskUri"
            Write-Output "`tstorage disk: $diskName"
        }
#>
    }
}

Write-Output "Finished!!!"
