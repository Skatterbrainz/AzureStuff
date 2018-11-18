[CmdletBinding()]
param()

$VerbosePreference = "Continue"

<#
The following variables are defined under Assets for the Automation Account:
#>

$Rg  = Get-AutomationVariable -Name 'ResourceGroupName'
$Sa1 = Get-AutomationVariable -Name 'SourceStorageAccount'
$Sa2 = Get-AutomationVariable -Name 'DestinationStorageAccount'
$Sk1 = Get-AutomationVariable -Name 'StorageAccountKey1'
$Sk2 = Get-AutomationVariable -Name 'StorageAccountKey2'
$DCN = Get-AutomationVariable -Name 'DestinationContainer'
$BDF = Get-AutomationVariable -Name 'BackupDateFormat'

try {
    $Conn = Get-AutomationConnection -Name AzureRunAsConnection 
    $TenantID = $conn.TenantID
    $AppID = $conn.ApplicationID
    $SubId = $conn.SubscriptionID
    Write-Output "SubscriptionID: $SubId"
}
catch {
    Write-Error $Error[0].Exception.Message
    break
}

try {
    Add-AzureRMAccount -ServicePrincipal -Tenant $TenantID -ApplicationId $AppID -CertificateThumbprint $Conn.CertificateThumbprint
    Write-Output "Add-AzureRMAccount: successful"
    $azureContext = Select-AzureRmSubscription -SubscriptionId $SubID
    Write-Output "Select-AzureRmSubscription: successful"
}
catch {
    Write-Error $Error[0].Exception.Message
    break    
}

try {
    $sc1 = Get-AzureRmStorageContainer -ResourceGroupName $Rg -StorageAccountName $Sa1 -ErrorAction Stop
    Write-Verbose "connected to storage container: $Sa1"
    Write-Verbose "$($sc1.Count) containers in $Sa1"
    $sc1 = $sc1 | Where-Object {$_.Name -ne 'azure-webjobs-hosts'}
}
catch {
    Write-Error $Error[0].Exception.Message
    break
}
Write-Verbose "source containers: $($sc1.Name -join ',')"
Write-Verbose "getting storage contexts"
try {
    $context1 = New-AzureStorageContext -StorageAccountName $Sa1 -StorageAccountKey $Sk1
    $context2 = New-AzureStorageContext -StorageAccountName $Sa2 -StorageAccountKey $Sk2
    Write-Verbose "storage contexts established"
}
catch {
    Write-Error $Error[0].Exception.Message
    break
}

Write-Verbose "getting destination container"
try {
    $sc2 = Get-AzureRmStorageContainer -ResourceGroupName $Rg -StorageAccountName $Sa2 -Name $DCN -ErrorAction Stop
    Write-Verbose "container $DCN exists under $Sa2"
    $destBlobs = (Get-AzureStorageBlob -Container $DCN -Context $Context2).Name
    Write-Verbose "$($destBlobs.count) destination blobs found in [$DCN]"
    Write-Verbose $($destBlobs -join ',')
}
catch {
    try {
        $sc2 = New-AzureRmStorageContainer -ResourceGroupName $Rg -StorageAccountName $Sa2 -Name $DCN -ErrorAction Stop
        Write-Verbose "container $DCN created under $Sa2"
        # $destBlobs = @()
    }
    catch {
        Write-Error $Error[0].Exception.Message
        break
    }
}

foreach ($sc in $sc1) {
    $sourceContainer = $sc.Name
    Write-Verbose "source container: $sourceContainer"
    try {
        $srcBlobs = Get-AzureStorageBlob -Container $sourceContainer -Context $context1 -ErrorAction Stop
        Write-Verbose "$($srcBlobs.Count) blob containers found in: $Sa1"
        foreach ($blob in $srcBlobs) {
            $srcBlob = $blob.Name
            $destPrefix = $sourceContainer+'-'+(Get-Date -f $BDF)
            $destBlob = "$destPrefix`/$srcBlob"
            if ($destBlobs -notcontains $destBlob) {
                Write-Verbose "destination: $destBlob does not exist"
                try {
                    Write-Verbose "copying [$srcBlob] from [$sourceContainer] to [$DCN] [$destBlob]"
                    # $copyJob = Start-AzureStorageBlobCopy -Context $context1 -SrcContainer $sourceContainer -SrcBlob $srcBlob -DestContainer $DCN -DestBlob $destBlob -DestContext $context2 -Force -Confirm:$False
                    Write-Verbose "copy completed"
                }
                catch {
                    Write-Verbose "copy failed!"
                    Write-Error $Error[0].Exception.Message
                }
            }
            else {
                Write-Verbose "destination: $destBlob already exists"
            }
        } # foreach
    }
    catch {
        Write-Error $Error[0].Exception.Message
        break
    }
} # foreach

Write-Output "done!"
