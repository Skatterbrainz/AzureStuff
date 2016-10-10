# https://mva.microsoft.com/en-US/training-courses/powershell-for-sql-data-professionals-16532?l=573qb2PgC_5405121157

Login-AzureRMAccount

$rgname   = "rg003"
$locname  = "East US"
$staname  = "dsStorageAcct3"
$subnet1  = "dssubnet3"
$vnetname = "dsvnet3"
$pipname  = "dspip3"
$domlab   = "vm-sql3"
$nicname  = "dsnic3"
$vmname   = "vmsql3"

$cred = Get-Credential -Message "Type the name and password for local admin account"
New-SzureRmResourceGroup -Name $rgname -Location $locname

#network assets
$subnet = New-AzureRmVirtualNetworkSubnetConfig -Name $subnet1 -AddressPrefix 10.0.0.0/24
$vnet   = New-AzureRmVirtualNetwork -Name $vnetname -ResourceGroupName $rgname -Location $locname -AddressPrefix 10.0.0.0/16 -Subnet $subnet
$pip    = New-AzureRmPublicIpAddress -Name $pipname -ResourceGroupName $rgname -Location $locname -AllocationMethod Dynamic -DomainNameLabel $domlab
$nic    = New-AzureRmNetworkInterface -Name $nicname -ResourceGroupName $rgname -Location $locname -SubnetId $vnet.Subnets[0].Id -PublicAddressId $pip.Id

#storage account
$storage = New-AzureRmStorageAccount -ResourceGroupName $rgname -Name $staname -Type Standard_LRS -Location $locname
$ospath = $storage.PrimaryEndpoints.Blob.ToString() + "vhds/$vmname.vhd"
$datapath = $storage.PrimaryEndpoints.Blob.ToString() + "vhds/$vmname.vhd"

#find image
Get-AzureRmVmImagePublisher -Location $locname | Where-Object {$_.PublisherName -like "*SQL*"}
Get-AzureRmVmImageOffer -Location $locname -PublisherName MicrosoftSQLServer
Get-AzureRmVmImageSku -Location $locname -PublisherName MicrosoftSQLServer -Offer SQL2016-WS2012R2