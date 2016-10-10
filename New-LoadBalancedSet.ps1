# Add Subnets to existing Virtual Network in Current Resource Group; create Public IP for FrontEnd, BackEnd Pool, Health Probe & finally the Load Balancer
# https://azure.microsoft.com/en-us/documentation/articles/load-balancer-get-started-internet-arm-ps/

$loc           = 'East US'
$vnetName      = 'GOvpn01'
$myRG          = 'RGvpn01'
$subnetname    = 'sub01'
$frontendname  = 'FE01'
$bepoolname    = 'BEPool01'
$PubIP         = 'PublicIp01'
$addressprefix = '10.21.6.0/24'
$PrivIP01      = '10.21.6.102'
$PrivIP02      = '10.21.6.103'
$DNSlabel      = 'kbblbdns01'
$NICname01     = 'nic01'
$NICname02     = 'nic02'
$HealthProbe   = 'HP01'
$lbname        = 'GOLB01'

$vnet = Get-AzureRmVirtualNetwork -ResourceGroupName $myRG -Name $vnetName
Add-AzureRmVirtualNetworkSubnetConfig -Name $subnetname -AddressPrefix $addressprefix -VirtualNetwork $vnet
$SubnetConfig = (Get-AzurermVirtualNetworkSubnetConfig -VirtualNetwork $vnet -Name $subnetname).Id
Set-AzureRmVirtualNetwork -VirtualNetwork $vnet

$PublicIp = New-AzureRmPublicIpAddress -Name $PubIP -ResourceGroupName $myRG -Location $loc -AllocationMethod Static -DomainNameLabel $DNSlabel
$frontendIP = New-AzureRmLoadBalancerFrontendIpConfig -Name $frontendname -PublicIpAddress $PublicIp 
$beaddresspool = New-AzureRmLoadBalancerBackendAddressPoolConfig -Name $bepoolname

$lbrule = New-AzureRmLoadBalancerRuleConfig -Name HTTP -FrontendIpConfiguration $frontendIP -BackendAddressPool $beaddresspool -Probe $HealthProbe -Protocol Tcp -FrontendPort 80 -BackendPort 80
$HealthProbe = New-AzureRmLoadBalancerProbeConfig -Name $HealthProbe -RequestPath 'HealthProbe.aspx' -Protocol http -Port 80 -IntervalInSeconds 15 -ProbeCount 2
$NRPLB = New-AzureRmLoadBalancer -ResourceGroupName $myRG -Name $lbname -Location $loc -FrontendIpConfiguration $frontendIP -LoadBalancingRule $lbrule -BackendAddressPool $beaddresspool -Probe $HealthProbe

# Get the Virtual Network and Virtual Network Subnet, where the NICs need to be created.

$vnet = Get-AzureRmVirtualNetwork -Name $vnetName -ResourceGroupName $myRG
$backendSubnet = Get-AzureRmVirtualNetworkSubnetConfig -Name $subnetname -VirtualNetwork $vnet
$backendnic1 = New-AzureRmNetworkInterface -ResourceGroupName $myRG -Name $NICname01 -Location $loc -PrivateIpAddress $PrivIP01 -Subnet $backendSubnet -LoadBalancerBackendAddressPool $nrplb.BackendAddressPools[0]
$backendnic2 = New-AzureRmNetworkInterface -ResourceGroupName $myRG -Name $NICname02 -Location $loc -PrivateIpAddress $PrivIP02 -Subnet $backendSubnet -LoadBalancerBackendAddressPool $nrplb.BackendAddressPools[0]

# Check the NICs
$backendnic1

# Load the load balancer resource into a variable
$lb = Get-AzureRmLoadBalancer -Name $lbname -ResourceGroupName $myRG

# Load the backend configuration to a variable.
$backend = Get-AzureRmLoadBalancerBackendAddressPoolConfig -Name $bepoolname -LoadBalancer $lb

# Load the already created network interface into a variable
$nic = Get-AzureRmNetworkInterface -Name $NICname01 -ResourceGroupName $myRG

# Change the backend configuration on the network interface
$nic.IpConfigurations[0].LoadBalancerBackendAddressPools = $backend

# Save the network interface object
Set-AzureRmNetworkInterface -NetworkInterface $nic

# Load the already created network interface (SECOND) into a variable
$nic = Get-AzureRmNetworkInterface -Name $NICname02 -ResourceGroupName $myRG

# Change the backend configuration on the network interface
$nic.IpConfigurations[0].LoadBalancerBackendAddressPools = $backend

# Save the network interface object
Set-AzureRmNetworkInterface -NetworkInterface $nic