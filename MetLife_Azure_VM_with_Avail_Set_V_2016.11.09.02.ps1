<#
.SYNOPSIS
	Create Azure ARM VM lab
.DESCRIPTION
	
.PARAMETER AccountID
	[string] (required) email address for tenant/subscription connection
.PARAMETER TenantId
	[string] (required) guid for tenant ID
.PARAMETER SubscriptionId
	[string] (required) guid for subscription ID
.PARAMETER ParamFile
    [string] (optional) CSV file with account, tenant and subscription ID info
.PARAMETER InputFile
	[string] (optional) name of CSV input file
.NOTES
	Version....... 2016.11.09.02
	Date Created:  09/08/2016
	Date Modified: 11/09/2016
#>


param (
    [parameter(Mandatory=$False)] [string] $ParamFile = "config.csv",
    [parameter(Mandatory=$False)] [string] $AccountID = "",
    [parameter(Mandatory=$False)] [string] $TenantId = "",
    [parameter(Mandatory=$False)] [string] $SubscriptionId = "",
    [parameter(Mandatory=$False)] [string] $InputFile = "gomet2.csv",
    [parameter(Mandatory=$False)] [switch] $NoVM
)
$azEnv = "AzureCloud"

$StartTime = Get-Date

if ($AccountID -ne "") {
    Write-Verbose "info: configuration read from parameter inputs."
}
else {
    if ($ParamFile -ne "") {
        $config = Import-Csv $ParamFile
        if ($config -ne $null) {
            $AccountID = $config.AccountID
            $TenantID = $config.TenantID
            $SubscriptionID = $config.SubscriptionID
            Write-Verbose "info: configuration read from input file: $ParamFile"
        }
        else {
            Write-Verbose "error: configuration file missing information."
            Break
        }
    }
    else {
        Write-Verbose "error: configuration file not found!"
        Break
    }
}

function Make-ResourceGroup {
    param ($rgn, $loc)
    Write-Verbose "[make-resourcegroup] $rgn $loc"
    $rgx = Get-AzureRmResourceGroup -Name $rgn -Location $loc -ErrorAction SilentlyContinue
    if ($rgx -eq $null) {
        Write-Verbose "info: creating resource group: $rgn..."
        $rgx = New-AzureRmResourceGroup -Name $rgn -Location $loc -ErrorAction SilentlyContinue
    }
    else {
        Write-Verbose "info: resource group already exists: $rgn"
    }
    $rgx
}

Write-Verbose "Checking if session is authenticated..."
if ($azCred -eq $null) {
    Write-Verbose "Authentication is required."
    $azCred = Login-AzureRmAccount -SubscriptionId $SubscriptionId -TenantId $TenantId
}
else {
    Write-Output "Authentication already confirmed."
}

Write-Verbose "Reading input file: $InputFile..."
$csvData = Import-Csv $InputFile

if ($csvData -ne $null) {
    
    Write-Output "Retrieved $($csvData.Length) rows for processing"

    foreach ($row in $csvData) {
        $Location       = $row.Location
	    $vmName         = $row.Name
        $sourceCont     = $row.sourceContainer
        $sourceVHD      = $row.SourceVHD
        $destCont       = $row.destinationContainer
	    $osDiskUri      = $row.osdiskUri
	    $saName         = $row.StorageAccount
        $StTemplate     = $row.SourceTemplate
        $storagesku     = $row.StorageSku
        $vmSize         = $row.Size
        $Publisher      = $row.PublisherName
        $Offer          = $row.Offer
        $Version        = $row.Version
        $Skus           = $row.Skus
        $privIP         = $row.PrivateIP
        $pubIP          = $row.PublicIP
        $vnetName       = $row.vnetName
        $subnetName     = $row.SubnetName
        $subnetPfx      = $row.SubnetRange
        $addressPfx     = $row.AddressRange
        $rgName         = $row.ResourceGroup
        $rgstore        = $row.StorageResGroup
        $rgnet          = $row.NetworkingResGroup
        $caching        = $row.caching
        $DataDiskSize1  = $row.DataDiskSize1
        $ASName         = $row.ASName
        $VmAdminUser    = $row.AdminUser
        $VmAdminPwd     = $row.AdminPwd
        $nicName        = "$vmName"+"nic1"
        $osdiskname     = "$vmName"+"os.vhd"
        $diskName       = "$vmName"+"osdisk"
        $datadiskname   = "$vmName"+"datadisk.vhd"
        $ipName         = "$vmName"+"pip1"

        Write-Verbose "---------------------------------------------------"
        Write-Verbose "Current row dataset..."
        Write-Verbose $row

        # check if first cell begins with ";" denoting a commented line
        if ($vmName.Substring(0,1) -ne ";") {
            Write-Output "---------------------------------------------------"
            if ((Get-AzureRmVM -VM $vmName -ResourceGroupName $rgName -ErrorAction SilentlyContinue) -ne $null) {
                Write-Output "VM $vmName already exists."
            }
            else {
                
                $subnet = $null
                $vnet   = $null

                $RowStart = Get-Date
                $rg  = Make-ResourceGroup -rgn $rgName -loc $location
                $rgs = Make-ResourceGroup -rgn $rgStore -loc $location
                $rgn = Make-ResourceGroup -rgn $rgnet -loc $location

                # Check Storage Account Availability
                $StorageAccountNameExists   = [bool](Get-AzureRmStorageAccountNameAvailability -Name $saName).NameAvailable
                $StNameExistsInTheTenant    = [bool](Get-AzureRmStorageAccount | ?{$_.StorageAccountName -eq "$saName"})
                if ((!($StorageAccountNameExists)) -and (!($StNameExistsInTheTenant))){
                    Write-Output "Storage account" $saName "name already taken"
                    Write-Output "Please choose another Storage Account Name"
                    Write-Output "This Powershell command can be used: Get-AzureRmStorageAccountNameAvailability -Name"
                    Break
                }
                else {
                    Write-Verbose "Storage account: $saName is either available or already yours"
                }
                # Storage Account Logic
                if (!($StNameExistsInTheTenant)){
                    Write-Verbose "Creating storage account $saName"
                    $stAcct = New-AzureRmStorageAccount -ResourceGroupName $rgstore -Name $saName -SkuName $storagesku -Kind Storage -Location $Location -ErrorAction SilentlyContinue
                }
                else {
                    Write-Verbose "Getting existing account $saName"
                    $stAcct = (Get-AzureRmStorageAccount | ?{$_.StorageAccountName -eq "$saName"})
                }
                $stURI = $stAcct.PrimaryEndpoints.Blob.ToString()
            
                # check if Source VHD is specified
                if ($sourceVHD -ne "") {
                    $stTemplateTemp     = (Get-AzureRmStorageAccount | ?{$_.StorageAccountName -eq "$StTemplate"})
                    $StTemplateuri      = $stTemplateTemp.PrimaryEndpoints.Blob.ToString()
                    $StorageContext     = (Get-AzureRmStorageAccount -ResourceGroupName $rgstore -Name $saName).context
                    $CheckForSourceVHD  = [bool](Get-AzureStorageBlob -Context $StorageContext -Container $sourceCont | ? {$_.name -eq $sourceVHD})
                    #$CheckForSourceVHDB = [bool]$CheckForSourceVHD
                    if (($imageUri -ne "") -and ($Publisher -eq "") -and (!($CheckForSourceVHD))){
                        Write-Output "Source image not found (.vhd): $sourceVHD"
                        Break
                    }    
                    else {
                        Write-Verbose "Source image found or this is a Marketplace build"
                    }
                }

                # Storage Account
                $stAcct = (Get-AzureRmStorageAccount | ?{$_.StorageAccountName -eq "$saName"})
                if ($stAcct -eq $null) {
                    Write-Output "Creating storage account: $saName..."
                    Write-Verbose "Name: $saName`nResourceGroup: $rgStore`nSkuName: $storagesku"
                    $stAcct = New-AzureRmStorageAccount -ResourceGroupName $rgstore -Name $saName -SkuName $storagesku -Kind Storage -Location $Location #-ErrorAction SilentlyContinue
                }
                else {
                    Write-Verbose "Storage account already exists: $saName"
                }
                if ($stAcct -ne $null) {
                    Write-Verbose "Getting storage account URI..."
                    $stURI = $stAcct.PrimaryEndpoints.Blob.ToString()
                    Write-Verbose "Storage account URI: $stURI"
                }

                # Prep the Subnet
                Write-Verbose "==================================="
                Write-Verbose "SubnetName...: $subnetName"
                Write-Verbose "VnetName.....: $vnetName"
                Write-Verbose "==================================="

                # BOTH VNET AND SUBNET EXISTS
                if ((((Get-AzureRmVirtualNetwork).Subnets | ?{$_.Name -ne "$subnetName"}) -eq $null) -and ((Get-AzureRmVirtualNetwork | ?{$_.Name -eq "$vnetName"}) -ne $null)) {
                    #((Get-AzureRmVirtualNetwork -Name $vnetName -ResourceGroupName $rgNet).Subnets | ?{$_.Name -eq "$subnetName"}) {
                    #write-Verbose "A1..." $vnet
                    #Write-Verbose "B1..." ((Get-AzureRmVirtualNetwork).Subnets | ?{$_.Name -eq "$subnetName"})
                    Write-Verbose "condition 1 = vnet and subnet BOTH EXIST"
                    $subnet = ((Get-AzureRmVirtualNetwork).Subnets | ?{$_.Name -eq "$subnetName"}).Id
                }
                # NEITHER VNET OR SUBNET EXISTS
                elseif ((((Get-AzureRmVirtualNetwork).Subnets | ?{$_.Name -eq "$subnetName"}) -eq $null) -and ((Get-AzureRmVirtualNetwork | ?{$_.Name -eq "$vnetName"}) -eq $null)) {
                    Write-verbose "A2... $vnet"
                    Write-verbose "B2... $subnet"
                    Write-Verbose "condition 2 = NEITHER EXIST: vnet or subnet"
                    $subnet = New-AzureRmVirtualNetworkSubnetConfig -Name $subnetName -AddressPrefix $subnetPfx
                    $vnet   = New-AzureRmVirtualNetwork -Name $vnetName -ResourceGroupName $rgnet -Location $Location -AddressPrefix $addressPfx -Subnet $subnet
                    $subnet = ((Get-AzureRmVirtualNetwork).Subnets | ?{$_.Name -eq "$subnetName"}).Id
                }
                # SUBNET EXISTS but vnet DOES NOT EXIST
                elseif ((Get-AzureRmVirtualNetwork | ?{$_.Name -eq "$vnetName"}) -eq $null) {
                    Write-Verbose "condition 4"
                    Write-Verbose "A4... vnet does not exist" 
                    if ($subnet -eq $null) { 
                        Write-Verbose "B4... subnet does not exist" 
                    }
                    else {
                        Write-Verbose "B4... subnet DOES exist"
                    }
                    $subnet = New-AzureRmVirtualNetworkSubnetConfig -Name $subnetName -AddressPrefix $subnetPfx
                    $vnet = (Get-AzureRmVirtualNetwork | ?{$_.Name -eq "$vnetName"})
                    Add-AzureRmVirtualNetworkSubnetConfig -Name $subnetName -VirtualNetwork $vnet -AddressPrefix $subnetPfx | Out-Null
                    $vnet   = Set-AzureRmVirtualNetwork -VirtualNetwork $vnet
                    $subnet = ((Get-AzureRmVirtualNetwork).Subnets | ?{$_.Name -eq "$subnetName"}).Id
                }
                # VNET EXISTS but SUBNET DOES NOT EXIST
                else {
                    Write-Verbose "condition 5"
                    if ((Get-AzureRmVirtualNetwork | ?{$_.Name -eq "$vnetName"}) -eq $null) {
                        Write-Verbose "vnet is NULL"
                    }
                    else {
                        Write-Verbose "B5... vnet EXISTS"
                        $vnet = (Get-AzureRmVirtualNetwork | ?{$_.Name -eq "$vnetName"})
                    }
                    if (((Get-AzureRmVirtualNetwork).Subnets | ?{$_.Name -eq "$subnetName"}) -eq $null) {
                        Write-Verbose "B5... adding subnet to vnet..."
                        $subnet = New-AzureRmVirtualNetworkSubnetConfig -Name $subnetName -AddressPrefix $subnetPfx
                        $vnet = (Get-AzureRmVirtualNetwork | ?{$_.Name -eq "$vnetName"})
                        Add-AzureRmVirtualNetworkSubnetConfig -Name $subnetName -VirtualNetwork $vnet -AddressPrefix $subnetPfx | Out-Null
                        $vnet   = Set-AzureRmVirtualNetwork -VirtualNetwork $vnet
                        $subnet = ((Get-AzureRmVirtualNetwork).Subnets | ?{$_.Name -eq "$subnetName"}).Id
                    }
                    else {
                        Write-Verbose "B5... subnet EXISTS"
                        $subnet = ((Get-AzureRmVirtualNetwork).Subnets | ?{$_.Name -eq "$subnetName"}).Id
                    }
                }

                # Create VM NIC / Check for requested Public IP Address
                If ($pubIP -ne "") {
                    Write-Verbose "Creating public IP: $ipName..."
                    $pip = New-AzureRmPublicIpAddress -Name $ipName -ResourceGroupName $rgName -Location $Location -AllocationMethod Static
                    Write-Verbose "Creating NIC: $nicName..."
                    $nic = New-AzureRmNetworkInterface -Name $nicName -ResourceGroupName $rgName -Location $Location -SubnetId $subnet -PublicIpAddressId $pip.Id -PrivateIpAddress $privIP
                }
                else {
                    Write-Verbose "No public IP address specified for $vmName"
                    Write-Verbose "Creating NIC: $nicName..."
                    $nic = New-AzureRmNetworkInterface -Name $nicName -ResourceGroupName $rgName -Location $Location -SubnetId $subnet -PrivateIpAddress $privIP
                }

                Write-Verbose "Preparing credentials for VM Local Admin..."

                $SecurePassword = ConvertTo-SecureString "$VmAdminPwd" -AsPlainText -Force
                $Credential = New-Object System.Management.Automation.PSCredential ($VmAdminUser, $SecurePassword); 
            
                # Prep Availability Set
                if ($ASName -ne "") {
                    Write-Verbose "Availability set specified: $asname"
                    $aset1 = Get-AzureRmAvailabilitySet -ResourceGroupName $rgName -Name $asName -ErrorAction SilentlyContinue
                    if (!($aset1)) {
                        Write-Verbose "Creating availability set: $asname"
                        $aset1 = New-AzureRmAvailabilitySet -ResourceGroupName $rgName -Name $asname -Location $location
                    }
                    else {
                        Write-Verbose "Availability set already exists: $asname"
                    }
                    Write-Verbose "Creating VM configuration with availability set: $vmName..."
                    $vm = New-AzureRmVMConfig -VMName $vmName -VMSize $vmSize -AvailabilitySetId $aset1.Id
                }
                else {
                    Write-Verbose "Creating VM configuration: $vmName..."
                    $vm = New-AzureRmVMConfig -VMName $vmName -VMSize $vmSize
                }

                Write-Verbose "Configuring VM OS and NIC association..."
                # NOTE: customer may want to disable ProvisionVMAgent parameter ***
                $vm = Set-AzureRmVMOperatingSystem -VM $vm -Windows -ComputerName $vmName -Credential $Credential -ProvisionVMAgent -EnableAutoUpdate
                $vm = Add-AzureRmVMNetworkInterface -VM $vm -Id $nic.Id
            
                # Prep the VM OS Disk
                $osDiskUri   = "$stURI"+"$destCont"+"/$osdiskname"      
                if ($Publisher -eq "") { 
                    Write-Verbose "Image from Source VHD $osDiskUri"
                    $imageUri = "$stURI"+"$sourceCont"+"/$sourceVHD"
                    Write-Verbose "Disk image uri is $imageUri"
                    $vm = Set-AzureRmVMOSDisk -VM $vm -Name $diskName -VhdUri $osDiskUri -CreateOption FromImage -SourceImageUri $imageUri -Windows
                }
                else {
                    Write-Verbose "Disk blob uri is $osDiskUri"
                    Write-Verbose "Marketplace Image from publisher $Publisher"
                    $vm = Set-AzureRmVMOSDisk -VM $vm -Name $diskName -VhdUri $osDiskUri -CreateOption FromImage
                    $vm = Set-AzureRmVMSourceImage -VM $vm -PublisherName $Publisher -Offer $Offer -Skus $Skus -Version $Version
                }
            
                # Create the Virtual Machine
                Write-Output "Creating virtual machine: $vmName..."
                $newvm = New-AzureRmVM -ResourceGroupName $rgName -Location $Location -VM $vm

                # Prep the VM Data Disk (if required)
                if ($DataDiskSize1 -ne "") {
                    Write-Verbose "Creating Data Disk: $datadiskname"     
                    $dataDiskUri = "$stURI"+"$destCont"+"/$datadiskname"
		            Write-Verbose "Data Disk URI: $dataDiskUri"
                    $vm = Get-AzureRmVM -ResourceGroupName $rgName -Name $vmName 
                    Write-Output "Attaching data disk to VM..."
                    Add-AzureRmVMDataDisk -VM $vm -Name $datadiskname -VhdUri $dataDiskUri -Caching $Caching -DiskSizeinGB $DataDiskSize1 -CreateOption Empty | Out-Null
                    Update-AzureRmVM -ResourceGroupName $rgName -VM $vm | Out-Null
                }
                else {
                    Write-Verbose "No Data Disk Requested for $vmName"
                }
            
                # Write Results to Screen
                $vmNic = Get-AzureRmNetworkInterface -Name $nicName -ResourceGroupName $rgName
                $pvtIP = $($vmNic.IpConfigurations).PrivateIpAddress
                Write-Verbose "`tPrivate IP: $pvtIP"
                If ($pubIP -ne "") {
                    $pubIP = $(Get-AzureRmPublicIpAddress -Name $ipName -ResourceGroupName $rgname).IpAddress
                    Write-Verbose "`tPublic IP: $pub"
                }
                Write-Verbose "*** Virtual machine completed! $vmName"
                $RowStop = Get-Date
                $RunTime = [math]::Round(($RowStop - $RowStart).TotalMinutes,2)
                Write-Output "Virtual Machine: $vmName, completed in $RunTime minutes"
            }
        }
    }
}

$StopTime = Get-Date
$RunTime = [math]::Round(($StopTime - $StartTime).TotalMinutes,2)
Write-Host "Finished!!! Runtime was $RunTime minutes"
