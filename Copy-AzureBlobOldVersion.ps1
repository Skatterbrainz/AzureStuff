#requires -version 3
#requires -modules AzureRM
<#
.SYNOPSIS
    Copy-AzureBlob copies a Blob file from one resource group, storage account
    and container, to another resource group, storage account, and container.

.PARAMETER SrcBlob
    [string] Name of blob (file) to copy from source container.

.PARAMETER SrcResourceGroupName
    [string] Name of Resource Group where Source storage account resides.

.PARAMETER SrcContainerName
    [string] Name of Container under Source storage account where Source file resides.

.PARAMETER SrcStorageAccountName
    [string] Name of Storage Account which contains the Source File to copy.

.PARAMETER DestResourceGroupName
    [string] Name of Resource Group where Destination Storage Account and Container
    reside, in which Source File will be copied to.

.PARAMETER DestContainerName
    [string] Name of Destination Container where Source File will be copied to.

.PARAMETER DestStorageAccountName
    [string] Name of Destination Storage Account which holds the Storage Container
    where Source File will be copied to.

.PARAMETER OverWrite
    [switch] Forces overwrite of existing Source File in the destination container.

.NOTES
    Requires a valid Azure RM login session.
    If Source File exists in the specified destination (container) it will not be overwritten
#>

function Copy-AzureSourceVHD {
    param (
        [parameter(Mandatory=$True, HelpMessage="Source Blob name")] 
            [ValidateNotNullOrEmpty()]
            [string] $SourceBlob,
        [parameter(Mandatory=$True, HelpMessage="Source Resource Group name")] 
            [ValidateNotNullOrEmpty()]
            [string] $SrcResourceGroupName,
        [parameter(Mandatory=$True, HelpMessage="Source Container name")] 
            [ValidateNotNullOrEmpty()]
            [string] $SrcContainerName,
        [parameter(Mandatory=$True, HelpMessage="Source Storage Account name")] 
            [ValidateNotNullOrEmpty()]
            [string] $SrcStorageAccountName,
        [parameter(Mandatory=$True, HelpMessage="Target Resource Group name")] 
            [ValidateNotNullOrEmpty()]
            [string] $DestResourceGroupName,
        [parameter(Mandatory=$True, HelpMessage="Target Container name")] 
            [ValidateNotNullOrEmpty()]
            [string] $DestContainerName,
        [parameter(Mandatory=$True, HelpMessage="Target Storage Account name")] 
            [ValidateNotNullOrEmpty()]
            [string] $DestStorageAccountName,
        [parameter(Mandatory=$False, HelpMessage="Overwrite Destination if existing")] 
            [switch] $OverWrite = $False
    )
    Write-Verbose "[copy-azuresourcevhd] $SourceBlob"
    Write-Verbose "info: SrcResourceGroupName..... $SrcResourceGroupName"
    Write-Verbose "info: DestResourceGroupName.... $DestResourceGroupName"
    Write-Verbose "info: SrcStorageAccountName.... $SrcStorageAccountName"
    Write-Verbose "info: DestStorageAccountName... $DestStorageAccountName"
    Write-Verbose "info: SrcContainerName......... $SrcContainerName"
    Write-Verbose "info: DestContainerName........ $DestContainerName"

    $SourceStorageKey = (Get-AzureRmStorageAccountKey -ResourceGroupName $SrcResourceGroupName -Name $SrcStorageAccountName)[0].Value
    $DestStorageKey   = (Get-AzureRmStorageAccountKey -ResourceGroupName $DestResourceGroupName -Name $DestStorageAccountName)[0].Value

    $SourceStorageContext = New-AzureStorageContext –StorageAccountName $SourceStorageAccount -StorageAccountKey $SourceStorageKey
    $DestStorageContext   = New-AzureStorageContext –StorageAccountName $DestStorageAccountName -StorageAccountKey $DestStorageKey

    $Blobs = (Get-AzureStorageBlob -Context $SourceStorageContext -Container $SrcContainerName | ?{$_.Name -eq $SourceBlob})
    $BlobCpyAry = @()
    
    $DestBlobs = (Get-AzureStorageBlob -Context $DestStorageContext -Container $DestContainerName | ?{$_.Name -eq $SourceBlob})
    if ((!($OverWrite)) -and ($DestBlobs -ne $null)) {
        Write-Output "$SourceBlob already exists in destination."
    }
    else {
        Write-Verbose "info: Copying blob objects..."
        if (!($TestMode)) {
            foreach ($Blob in $Blobs) {
                Write-Verbose "info: copying $($Blob.Name)..."
                $BlobCopy = Start-CopyAzureStorageBlob -Context $SourceStorageContext -SrcContainer $SourceContainer -SrcBlob $Blob.Name -DestContext $DestStorageContext -DestContainer $DestContainer -DestBlob $Blob.Name -Force
                $BlobCpyAry += $BlobCopy
            }

            foreach ($BlobCopy in $BlobCpyAry) {
                $CopyState = $BlobCopy | Get-AzureStorageBlobCopyState
                $Message = $CopyState.Source.AbsolutePath + " " + $CopyState.Status + " {0:N2}%" -f (($CopyState.BytesCopied/$CopyState.TotalBytes)*100) 
                Write-Output $Message
            }
        }
        else {
            foreach ($Blob in $Blobs) {
                Write-Verbose "test: copying $($Blob.Name)..."
            }
        }
    }
    $(Get-AzureStorageBlob -Context $DestStorageContext -Container $DestContainerName | 
        Where-Object {$_.Name -eq $SourceBlob})
}
