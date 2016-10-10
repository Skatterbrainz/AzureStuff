#Login in to AzureRM Account
Login-AzureRmAccount

#Set variables
$resourcegroup = 'IntroAzureSQL'
$location = 'West US'
$servername = 'msf-sqlintro'
$dbname = 'msf-sqlintrodb'
$localIP = (Invoke-WebRequest -Uri https://api.ipify.org).Content.trim()
$cred = Get-Credential -Message "Enter in SQL Admin credentials"

#Create Resource Group to hold SQL components
New-AzureRmResourceGroup -Name $resourcegroup -Location $location

#Create SQL Server
New-AzureRmSqlServer -ResourceGroupName $resourcegroup -Location $location -ServerName $servername -SqlAdministratorCredentials $cred -ServerVersion '12.0'

#Create Server Firewall rules
New-AzureRmSqlServerFirewallRule -ResourceGroupName $resourcegroup -ServerName $servername -AllowAllAzureIPs
New-AzureRmSqlServerFirewallRule -ResourceGroupName $resourcegroup -ServerName $servername -FirewallRuleName 'IntroUserFirewall' -StartIpAddress $localIP -EndIpAddress $localIP

#Create Database
New-AzureRmSqlDatabase -ResourceGroupName $resourcegroup -ServerName $servername -Edition Standard -DatabaseName $dbname -RequestedServiceObjectiveName 'S0'

#Connect SSMS to the new session
$cmd = "SSMS -S '$servername.database.windows.net' -d 'master' -U '$($cred.UserName)' -p '$($cred.GetNetworkCredential().Password)' -nosplash"
Invoke-Expression $cmd