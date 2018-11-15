#requires -version 5.0
#requires -modules AzureRM.Storage
<#
.DESCRIPTION
    Backup Azure Blob Containers from one Storage Account to Another.
    Copies each source container and blob to a date-stamped name in the second account.
    Example: SA1\container1\folder\133.txt --> SA2\backups\container1-20181114\folder\133.txt
.PARAMETER ConfigFile
    Path to JSON configuration file
.PARAMETER Force
    Force overwrite of existing targets (destinations) if they already exist
.EXAMPLE 
    .\Copy-AzureBlobs.ps1 -ConfigFile .\myconfig.json
.EXAMPLE
    .\Copy-AzureBlobs.ps1 -ConfigFile .\myconfig.json -Force -Verbose -WhatIf
.EXAMPLE
    .\Copy-AzureBlobs.ps1 -ConfigFile .\myconfig.json -Force -ResetCredentials
.NOTES
    1.0.0 - 2018/11/14 - First release (David Stein, Catapult Systems)
#>

[CmdletBinding(SupportsShouldProcess=$True)]
param (
    [parameter(Mandatory=$True, HelpMessage="Path to configuration file")]
    [ValidateNotNullOrEmpty()]
    [string] $ConfigFile,
    [parameter(Mandatory=$False, HelpMessage="Force backups even when targets already exist")]
    [switch] $Force,
    [parameter(Mandatory=$False, HelpMessage="Force credential reset")]
    [switch] $ResetCredentials
)
$time1 = Get-Date

function Invoke-AzureBlobBackup {
    [CmdletBinding(SupportsShouldProcess=$True)]
    param (
        [parameter(Mandatory=$False, HelpMessage="List of source containers to exclude from backups")]
            [string[]] $ExcludeContainers
    )
    Write-Verbose "connecting to storage accounts"

    $context1 = New-AzureStorageContext -StorageAccountName $SourceStorageAccount -StorageAccountKey $StorageAccountKey1
    $context2 = New-AzureStorageContext -StorageAccountName $DestinationStorageAccount -StorageAccountKey $StorageAccountKey2

    Write-Verbose "getting storage containers"

    $sc1 = Get-AzureRmStorageContainer -ResourceGroupName $ResourceGroupName -StorageAccountName $SourceStorageAccount
    if ($ExcludeContainers.Count -gt 0) {
        $sc1 = $sc1 | ?{$ExcludeContainers -notcontains $_.Name}
    }

    Write-Verbose "validating destination container [$DestinationContainer]"
    try {
        $sc2 = Get-AzureRmStorageContainer -ResourceGroupName $ResourceGroupName -StorageAccountName $DestinationStorageAccount -Name $DestinationContainer -ErrorAction Stop
        Write-Verbose "container [$DestinationContainer] exists in destination"
        $destBlobs = (Get-AzureStorageBlob -Container $DestinationContainer -Context $Context2).Name
        Write-Verbose "$($destBlobs.count) destination blobs found in [$DestinationContainer]"
        Write-Verbose $($destBlobs -join ',')
    }
    catch {
        Write-Verbose "container [$DestinationContainer] not found in destination, creating it now"
        try {
            $c2 = New-AzureRmStorageContainer -ResourceGroupName $ResourceGroupName -StorageAccountName $DestinationStorageAccount -Name $DestinationContainer
        }
        catch {
            $stopEverything = $True
            Write-Error $Error[0].Exception.Message
            break
        }
    }

    Write-Verbose "enumerating source containers"
    $countall = 0
    $ccount = 0
    foreach($sc in $sc1) {
        $sourceContainer = $sc.Name
        Write-Verbose "source container: $sourceContainer"

        $srcBlobs  = Get-AzureStorageBlob -Container $sourceContainer -Context $context1
        Write-Verbose "------------------------- $sourceContainer ---------------------------------"
        Write-Verbose "$($srcBlobs.count) source blobs found in [$sourceContainer]"
        #$srcBlobs

        Write-Verbose "copying blobs to [$DestinationContainer]..."
    
        foreach ($blob in $srcBlobs) {
            $countall++
            $srcBlob = $blob.Name
            $destPrefix = $sourceContainer+'-'+(Get-Date -f $BackupDateFormat)
            $destBlob = "$destPrefix`/$srcBlob"
            if ($Force -or ($destBlobs -notcontains $destBlob)) {
                Write-Verbose "copy [$srcBlob] to [$destBlob]"
                try {
                    $copyjob = Start-AzureStorageBlobCopy -Context $context1 -SrcContainer $sourceContainer -SrcBlob $srcBlob -DestContainer $DestinationContainer -DestBlob "$destBlob" -DestContext $context2 -Force -Confirm:$False
                    Write-Verbose "copy successful"
                    $ccount++
                }
                catch {
                    Write-Error $Error[0].Exception.Message
                }
            }
            else {
                Write-Verbose "blob [$destBlob] already backed up"
            }
        }
    }
}

function Get-AzureCredentials {
    [CmdletBinding()]
    param (
        [parameter(Mandatory=$True, HelpMessage="Azure Subscription UserName")]
        [ValidateNotNullOrEmpty()]
        [string] $AzureUserID,
        [parameter(Mandatory=$True, HelpMessage="Azure Subscription Name")]
        [ValidateNotNullOrEmpty()]
        [string] $SubscriptionName,
        [parameter(Mandatory=$False, HelpMessage="Credential file basename")]
        [ValidateNotNullOrEmpty()]
        [string] $CredentialName = "cred",
        [parameter(Mandatory=$False, HelpMessage="Force credentials reset")]
        [switch] $ForceUpdate
    )
    $ProfilePath = ".\$CredentialName.json"
    Write-Verbose "searching for $ProfilePath"
    if (Test-Path $ProfilePath) {
        if ($ForceUpdate) {
            Write-Verbose "deleting credential storage file: $ProfilePath"
            try {
                Get-Item -Path $ProfilePath -ErrorAction SilentlyContinue | Remove-Item -Force -WhatIf:$False
            }
            catch {}
            Write-Verbose "stored credential removed. prompt for credentials to create new file"
            try {
                $pwd = Get-Credential -UserName $AzureUserID -Message "Azure Credentials" -ErrorAction Stop
                $pwd.password | ConvertFrom-SecureString | Set-Content $ProfilePath -WhatIf:$False -ErrorAction Stop
                Write-Verbose "$ProfilePath has been updated"
            }
            catch {
                Write-Warning "$ProfilePath was NOT updated!"
            }
            try {
                $pwd = Get-Content $ProfilePath | ConvertTo-SecureString -Force
                $azCred = New-Object System.Management.Automation.PSCredential -ArgumentList $AzureUserID, $pwd
            }
            catch {
                Write-Error $Error[0].Exception.Message
                break
            }
        }
        else {
            Write-Verbose "$ProfilePath was found. importing contents"
            try {
                $pwd = Get-Content $ProfilePath | ConvertTo-SecureString -Force
                $azCred = New-Object System.Management.Automation.PSCredential -ArgumentList $AzureUserID, $pwd
            }
            catch {
                Write-Error $Error[0].Exception.Message
                break
            }
        }
    }
    else {
        Write-Verbose "$ProfilePath not found. prompt for credentials to create new file"
        try {
            $pwd = Get-Credential -UserName $AzureUserID -Message "Azure Credentials" -ErrorAction Stop
            $pwd.password | ConvertFrom-SecureString | Set-Content $ProfilePath -WhatIf:$False -ErrorAction Stop
            Write-Verbose '$ProfilePath has been updated'
        }
        catch {
            Write-Warning '$ProfilePath was NOT updated!!'
        }
        try {
            $pwd = Get-Content $ProfilePath | ConvertTo-SecureString -Force
            $azCred = New-Object System.Management.Automation.PSCredential -ArgumentList $AzureUserID, $pwd
        }
        catch {
            Write-Error $Error[0].Exception.Message
            break
        }
    }
    try {
        $azLogin = Connect-AzureRmAccount -Subscription $SubscriptionName -Credential $azCred -Environment $EnvironmentName -WhatIf:$False
        Write-Verbose "azure credentials verified"
    }
    catch {
        Write-Warning "azure credentials have expired. Prompt for new credentials"
        $azLogin = Connect-AzureRmAccount -Subscription $SubscriptionName -Environment $EnvironmentName -WhatIf:$False
    }
    $azLogin
}

function Get-AzureBackupConfig {
    param(
        [parameter(Mandatory=$True, HelpMessage="Path to configuration JSON file")]
        [ValidateNotNullOrEmpty()]
        [string] $FilePath
    )
    if (!(Test-Path $FilePath)) {
        Write-Warning "$FilePath not found!!"
        break
    }
    Get-Content -Raw -Path $FilePath | ConvertFrom-Json
}

if ($config = Get-AzureBackupConfig -FilePath $ConfigFile) {
    Write-Verbose "reading configuration data from file $ConfigFile"
    $config.psobject.properties | ForEach-Object{
        Set-Variable -Name $_.Name -Value $_.Value -Scope Script -WhatIf:$False
    }
    if ($ResetCredentials) {
        Get-AzureCredentials -AzureUserID $AzureUserID -SubscriptionName $SubscriptionName -CredentialName $CustomerName -ForceUpdate
    }
    if (Get-AzureCredentials -AzureUserID $AzureUserID -SubscriptionName $SubscriptionName -CredentialName $CustomerName) {
        Invoke-AzureBlobBackup -ExcludeContainers $ExcludedContainers
    }
    else {
        Write-Warning "run Set-AzureCredentials to update credential store and try running again"
    }
}
$time2 = Get-Date
Write-Verbose "completed. $countall total objects processed. $ccount were copied"
Write-Verbose "total runtime $($(New-TimeSpan -Start $time1 -End $time2).TotalSeconds) seconds"
