#Requires -Version 5.0

[CmdletBinding()]
param (
    [Parameter(Mandatory = $false)]
    [string] $Location = 'japaneast',

    [Parameter(Mandatory = $false)]
    [string] $ResourceGroupName = 'InstantShare',

    [Parameter(Mandatory = $false)]
    [string] $StorageAccountName = ('instantshare{0}' -f (Get-Date).ToString('ddHHmmss'))
)

function SetupStorageAccount
{
    param (
        [Parameter(Mandatory = $true)]
        [string] $ResourceGroupName,

        [Parameter(Mandatory = $true)]
        [string] $StorageAccountName,

        [Parameter(Mandatory = $true)]
        [string] $Location,

        [Parameter(Mandatory = $true)]
        [string] $StorageAccountVariableName
    )

    $storageAccount = Get-AzStorageAccount -ResourceGroupName $ResourceGroupName -Name $StorageAccountName -ErrorAction SilentlyContinue

    if ($storageAccount -ne $null)
    {
        Write-verbose -Message ('The storage account "{0}" was found within the resource group "{1}".' -f $StorageAccountName, $ResourceGroupName)
    }
    else
    {
        Write-verbose -Message ('The storage account "{0}" was not found within the resource group "{1}".' -f $StorageAccountName, $ResourceGroupName)

        Write-Verbose -Message 'Create a new resource group if the resource group does not exist.'
        New-AzResourceGroup -Name $ResourceGroupName -Location $Location -Force

        $nameAvailability = Get-AzStorageAccountNameAvailability -Name $StorageAccountName
        if ($nameAvailability.NameAvailable)
        {
            Write-Verbose -Message ('Create a new storage account "{0}" within the resource group "{1}".' -f $StorageAccountName, $ResourceGroupName)
            $params = @{
                ResourceGroupName      = $ResourceGroupName
                Location               = $Location
                Name                   = $StorageAccountName
                SkuName                = 'Standard_LRS'
                Kind                   = 'Storage'
                EnableHttpsTrafficOnly = $true
                MinimumTlsVersion      = 'TLS1_2'
                AllowBlobPublicAccess  = $false
            }
            $storageAccount = New-AzStorageAccount @params
        }
        else {
            throw $nameAvailability.Message
        }
    }

    $storageAccount | Format-List -Property 'StorageAccountName', 'ResourceGroupName', 'Location', 'Tags', 'Id'

    # Set variable in the parent scope.
    Set-Variable -Name $StorageAccountVariableName -Value $storageAccount -Scope '1'
}

function SetupContainer
{
    param (
        [Parameter(Mandatory = $true)]
        [Microsoft.Azure.Commands.Management.Storage.Models.PSStorageAccount] $StorageAccount,

        [Parameter(Mandatory = $true)]
        [string] $ContainerName,

        [Parameter(Mandatory = $true)]
        [string] $AccessPolicyName,

        [Parameter(Mandatory = $true)]
        [string] $ContainerCorsOriginVariableName,

        [Parameter(Mandatory = $true)]
        [string] $ContainerAccessPolicyVariableName
    )

    #
    # Create a new container if not exists.
    #

    $container = Get-AzStorageContainer -Context $StorageAccount.Context -Name $ContainerName -ErrorAction SilentlyContinue

    if ($container -ne $null)
    {
        Write-verbose -Message ('The container "{0}" was found within the storage account "{1}".' -f $ContainerName, $StorageAccount.StorageAccountName)
    }
    else {
        Write-Verbose -Message ('Create a new container "{0}" within the storage account "{1}".' -f $ContainerName, $StorageAccount.StorageAccountName)
        $container = New-AzStorageContainer -Context $StorageAccount.Context -Name $ContainerName -Permission Off
    }

    $container | Format-List -Property @{ Label = 'ContainerName'; Expression = { $_.Name } }, 'PublicAccess'

    #
    # Create a new access policy if not exists.
    #

    $params = @{
        Context     = $StorageAccount.Context
        Container   = $container.Name
        Policy      = $AccessPolicyName
        ErrorAction = [System.Management.Automation.ActionPreference]::SilentlyContinue
    }
    $containerAccessPolicy = Get-AzStorageContainerStoredAccessPolicy @params

    if ($containerAccessPolicy -ne $null)
    {
        Write-verbose -Message ('The container access policy "{0}" was already existed on the container "{1}".' -f $containerAccessPolicy.Policy, $container.Name)
    }
    else {
        Write-Verbose -Message ('Create a new access policy "{0}" to the container "{1}".' -f $AccessPolicyName, $container.Name)
        $params = @{
            Context    = $StorageAccount.Context
            Container  = $container.Name
            Policy     = $AccessPolicyName
            Permission = 'r'  # Read
            StartTime  = Get-Date
            ExpiryTime = (Get-Date).AddDays(21)  # Until three weeks after.
        }
        [void](New-AzStorageContainerStoredAccessPolicy @params)

        $params = @{
            Context   = $StorageAccount.Context
            Container = $container.Name
            Policy    = $AccessPolicyName
        }
        $containerAccessPolicy = Get-AzStorageContainerStoredAccessPolicy @params
    }

    $containerAccessPolicy | Format-List -Property @{ Label = 'PolicyName'; Expression = { $_.Policy } }, 'Permissions', 'StartTime', 'ExpiryTime'

    #
    # Set variable in the parent scope.
    #

    $containerCorsOrigin = $container.CloudBlobContainer.Uri.Scheme + '://' + $container.CloudBlobContainer.Uri.Authority
    Set-Variable -Name $ContainerCorsOriginVariableName -Value $containerCorsOrigin -Scope '1'
    Set-Variable -Name $ContainerAccessPolicyVariableName -Value $containerAccessPolicy -Scope '1'
}

function SetupTable
{
    param (
        [Parameter(Mandatory = $true)]
        [Microsoft.Azure.Commands.Management.Storage.Models.PSStorageAccount] $StorageAccount,

        [Parameter(Mandatory = $true)]
        [string] $TableName,

        [Parameter(Mandatory = $true)]
        [string] $ContainerCorsOrigin,

        [Parameter(Mandatory = $true)]
        [string] $AccessPolicyName,

        [Parameter(Mandatory = $true)]
        [string] $TableSasTokenVariableName
    )

    #
    # Create a new table if not exists.
    #

    $table = Get-AzStorageTable -Context $StorageAccount.Context -Name $TableName -ErrorAction SilentlyContinue
    if ($table -ne $null)
    {
        Write-verbose -Message ('The table "{0}" was found within the storage account "{1}".' -f $TableName, $StorageAccount.StorageAccountName)
    }
    else {
        Write-Verbose -Message ('Create a new table "{0}" within the storage account "{1}".' -f $TableName, $StorageAccount.StorageAccountName)
        $table = New-AzStorageTable -Context $StorageAccount.Context -Name $TableName
    }

    $table | Format-List -Property @{ Label = 'TableName'; Expression = { $_.Name } }, 'Uri'

    #
    # Add a new CORS rule to the table service.
    #

    Write-Verbose -Message ('Add a new CORS rule to the table service on the storage account "{0}".' -f $StorageAccount.StorageAccountName)

    $StorageAccount.Context.BlobEndPoint

    $newCorsRule = New-Object -TypeName 'Microsoft.WindowsAzure.Commands.Storage.Model.ResourceModel.PSCorsRule'
    $newCorsRule.AllowedOrigins = $ContainerCorsOrigin
    $newCorsRule.AllowedMethods = 'GET', 'PUT', 'OPTIONS'
    $newCorsRule.AllowedHeaders = '*'
    $newCorsRule.ExposedHeaders = '*'
    $newCorsRule.MaxAgeInSeconds = 60 * 60 * 24

    $corsRules = Get-AzStorageCORSRule -COntext $StorageAccount.Context -ServiceType Table
    $corsRules = $corsRules + $newCorsRule
    Set-AzStorageCORSRule -Context $StorageAccount.Context -ServiceType Table -CorsRules $corsRules

    $corsRules | Format-List -Property '*'

    #
    # Create a new access policy if not exists.
    #

    $params = @{
        Context     = $StorageAccount.Context
        Table       = $table.Name
        Policy      = $AccessPolicyName
        ErrorAction = [System.Management.Automation.ActionPreference]::SilentlyContinue
    }
    $tableAccessPolicy = Get-AzStorageTableStoredAccessPolicy @params

    if ($tableAccessPolicy -ne $null)
    {
        Write-verbose -Message ('The table access policy "{0}" was already existed on the table "{1}".' -f $tableAccessPolicy.Policy, $table.Name)
    }
    else {
        Write-Verbose -Message ('Create a new access policy "{0}" to the table "{1}".' -f $AccessPolicyName, $table.Name)

        $params = @{
            Context    = $StorageAccount.Context
            Table      = $table.Name
            Policy     = $AccessPolicyName
            Permission = 'rau'  # Read, Add, Update
            StartTime  = Get-Date
            ExpiryTime = (Get-Date).AddDays(21)  # Until three weeks after.
        }
        [void](New-AzStorageTableStoredAccessPolicy @params)

        $params = @{
            Context = $StorageAccount.Context
            Table   = $table.Name
            Policy  = $AccessPolicyName
        }
        $tableAccessPolicy = Get-AzStorageTableStoredAccessPolicy @params
    }

    $tableAccessPolicy | Format-List -Property @{ Label = 'PolicyName'; Expression = { $_.Policy } }, 'Permissions', 'StartTime', 'ExpiryTime'

    #
    # Create a new table SAS token.
    #

    $params = @{
        Context = $table.Context
        Name    = $table.name
        Policy  = $tableAccessPolicy.Policy
    }
    $tableSasToken = New-AzStorageTablesasToken @params

    $tableSasToken | Format-List -Property '*'

    #
    # Set variable in the parent scope.
    #

    Set-Variable -Name $TableSasTokenVariableName -Value $tableSasToken -Scope '1'
}

function SetupJsLibrary
{
    param (
        [Parameter(Mandatory = $true)]
        [System.IO.DirectoryInfo] $StageFolder,

        [Parameter(Mandatory = $true)]
        [Microsoft.Azure.Commands.Management.Storage.Models.PSStorageAccount] $StorageAccount,

        [Parameter(Mandatory = $true)]
        [string] $ContainerName,

        [Parameter(Mandatory = $true)]
        [string] $AccessPolicyName,

        [Parameter(Mandatory = $true)]
        [string] $JsLibraryUriWithSasVariableName
    )

    $JS_LIBRARY_DOWNLOAD_URI = 'https://aka.ms/downloadazurestoragejs'
    $JS_LIBRARY_FILE_NAME = 'azure-storage.table.min.js'

    #
    # Download the Azure Storage JavaScript Library.
    #

    Write-Verbose -Message 'Download the Azure Storage JavaScript Client Library for Browsers.'

    $libraryDownloadPath = Join-Path -Path $env:Temp -ChildPath 'azurestoragejs.instantshare.zip'
    Invoke-WebRequest -Method Get -Uri $JS_LIBRARY_DOWNLOAD_URI -OutFile $libraryDownloadPath -UseBasicParsing

    # Verify the file type of downloaded file by matching with zip file signature.
    $params = @{
        LiteralPath = $libraryDownloadPath
        TotalCount  = 4
    }
    if ((Get-Command -Name 'Get-Content').Parameters.ContainsKey('AsByteStream'))
    {
        # For PowerShell Core 6
        $params.AsByteStream = $true
    }
    else
    {
        # For PowerShell 5.x
        $params.Encoding = [Microsoft.PowerShell.Commands.FileSystemCmdletProviderEncoding]::Byte
    }
    $fileSignature = Get-Content @params
    if ((Compare-Object -ReferenceObject 0x50,0x4b,0x3,0x4 -DifferenceObject $fileSignature -PassThru) -ne $null)
    {
        throw ('Failed to the Azure Storage JavaScript library download, the response located at "{0}".' -f $libraryDownloadPath)
    }

    Write-Verbose -Message ('The library file download completed that saved to "{0}".' -f $libraryDownloadPath)

    $params = @{
        Path      = [System.IO.Path]::GetDirectoryName($libraryDownloadPath)
        ChildPath = [System.IO.Path]::GetFileNameWithoutExtension($libraryDownloadPath)
    }
    $libraryExpandFolderPath = Join-Path @params
    Expand-Archive -LiteralPath $libraryDownloadPath -DestinationPath $libraryExpandFolderPath -Force

    $libraryFile = Get-ChildItem -LiteralPath $libraryExpandFolderPath -File -Recurse -Filter $JS_LIBRARY_FILE_NAME

    Write-Verbose -Message ('Copy the library file to "{0}".' -f $StageFolder.FullName)
    Copy-Item -LiteralPath $libraryFile.FullName -Destination $StageFolder.FullName -Force

    Write-Verbose -Message ('Delete downloaded file "{0}".' -f $libraryDownloadPath)
    Remove-Item -LiteralPath $libraryDownloadPath -Force

    Write-Verbose -Message ('Delete working folder "{0}".' -f $libraryExpandFolderPath)
    Remove-Item -LiteralPath $libraryExpandFolderPath -Recurse -Force

    #
    # Upload the Azure Storage JavaScript Library.
    #

    $stagedLibraryFile = Get-ChildItem -LiteralPath $StageFolder.FullName -File -Filter $JS_LIBRARY_FILE_NAME

    $params = @{
        Context    = $StorageAccount.Context
        Container  = $ContainerName
        BlobType   = 'Block'
        File       = $stagedLibraryFile.FullName
        Properties = @{ ContentType = 'application/javascript' }
        Force      = $true
    }
    $libraryBlob = Set-AzStorageBlobContent @params

    $params = @{
        Context   = $libraryBlob.Context
        CloudBlob = $libraryBlob.ICloudBlob
        Policy    = $AccessPolicyName
    }
    $blobSasToken = New-AzStorageBlobSASToken @params

    $libraryUriWithSas = $libraryBlob.ICloudBlob.Uri.AbsoluteUri + $blobSasToken

    $libraryUriWithSas | Format-List -Property '*'

    #
    # Set variable in the parent scope.
    #

    Set-Variable -Name $JsLibraryUriWithSasVariableName -Value $libraryUriWithSas -Scope '1'
}

function SetupHtml
{
    param (
        [Parameter(Mandatory = $true)]
        [Microsoft.Azure.Commands.Management.Storage.Models.PSStorageAccount] $StorageAccount,

        [Parameter(Mandatory = $true)]
        [string] $TableName,

        [Parameter(Mandatory = $true)]
        [string] $TableSasToken,

        [Parameter(Mandatory = $true)]
        [string] $JsLibraryUriWithSas,

        [Parameter(Mandatory = $true)]
        [System.IO.DirectoryInfo] $StageFolder,

        [Parameter(Mandatory = $true)]
        [string] $ContainerName,

        [Parameter(Mandatory = $true)]
        [string] $AccessPolicyName,

        [Parameter(Mandatory = $true)]
        [string] $HtmlUriWithSasVariableName
    )

    $HTML_FILE_NAME = 'index.html'

    #
    # Create the HTML file.
    #

    $htmlFile = Get-ChildItem -LiteralPath $PSScriptRoot -File -Filter $HTML_FILE_NAME
    $htmlContent = Get-Content -LiteralPath $htmlFile.FullName -Encoding UTF8

    $htmlContent = $htmlContent -creplace '<STORAGE_ACCOUNT_NAME>', $StorageAccount.StorageAccountName
    $htmlContent = $htmlContent -creplace '<TABLE_SAS_TOKEN>', $TableSasToken.TrimStart('?')
    $htmlContent = $htmlContent -creplace '<TABLE_NAME>', $TableName
    $htmlContent = $htmlContent -creplace '<AZURE_STORAGE_TABLE_JS_LIBRARY_URI>', $JsLibraryUriWithSas

    $stagingHtmlFilePath = Join-Path -Path $StageFolder.FullName -ChildPath $HTML_FILE_NAME
    Set-Content -LiteralPath $stagingHtmlFilePath -Value $htmlContent -Encoding UTF8 -Force

    #
    # Upload the HTML file.
    #

    $stagedHtmlFile = Get-ChildItem -LiteralPath $StageFolder.FullName -File -Filter $HTML_FILE_NAME

    $params = @{
        Context    = $StorageAccount.Context
        Container  = $ContainerName
        BlobType   = 'Block'
        File       = $stagedHtmlFile.FullName
        Properties = @{ ContentType = 'text/html' }
        Force      = $true
    }
    $htmlBlob = Set-AzStorageBlobContent @params

    $params = @{
        Context   = $htmlBlob.Context
        CloudBlob = $htmlBlob.ICloudBlob
        Policy    = $AccessPolicyName
    }
    $blobSasToken = New-AzStorageBlobSASToken @params

    $htmlUriWithSas = $htmlBlob.ICloudBlob.Uri.AbsoluteUri + $blobSasToken

    $htmlUriWithSas | Format-List -Property '*'

    #
    # Set variable in the parent scope.
    #

    Set-Variable -Name $HtmlUriWithSasVariableName -Value $htmlUriWithSas -Scope '1'
}

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 3

$containerName = 'instantshare'
$containerAccessPolicyName = 'CInstantShare'
$tableName = 'instantshare'
$tableAccessPolicyName = 'TInstantShare'
$stageFolderName = 'stage'

Get-AzContext

$params = @{
    ResourceGroupName          = $ResourceGroupName
    StorageAccountName         = $StorageAccountName
    Location                   = $Location
    StorageAccountVariableName = 'storageAccount'
}
SetupStorageAccount @params

$params = @{
    StorageAccount                    = $storageAccount
    ContainerName                     = $containerName
    AccessPolicyName                  = $containerAccessPolicyName
    ContainerCorsOriginVariableName   = 'containerCorsOrigin'
    ContainerAccessPolicyVariableName = 'containerAccessPolicy'
}
SetupContainer @params

$params = @{
    StorageAccount            = $storageAccount
    TableName                 = $tableName
    ContainerCorsOrigin       = $containerCorsOrigin
    AccessPolicyName          = $tableAccessPolicyName
    TableSasTokenVariableName = 'tableSasToken'
}
SetupTable @params

Write-Verbose -Message ('Create a new stage folder.' -f (Join-Path -Path $PSScriptRoot -ChildPath $stageFolderName))
$stageFolder = New-Item -ItemType Directory -Path $PSScriptRoot -Name $stageFolderName -Force
$stageFolder | Format-List -Property '*'

$params = @{
    StageFolder                     = $stageFolder
    StorageAccount                  = $storageAccount
    ContainerName                   = $ContainerName
    AccessPolicyName                = $ContainerAccessPolicyName
    JsLibraryUriWithSasVariableName = 'libraryUriWithSas'
}
SetupJsLibrary @params

$params = @{
    StorageAccount             = $storageAccount
    TableName                  = $tableName
    TableSasToken              = $tableSasToken
    JsLibraryUriWithSas        = $libraryUriWithSas
    StageFolder                = $stageFolder
    ContainerName              = $containerName
    AccessPolicyName           = $containerAccessPolicyName
    HtmlUriWithSasVariableName = 'htmlUriWithSas'
}
SetupHtml @params

[PSCustomObject] @{  AppUri = $htmlUriWithSas } | Format-List

if ((Get-Command -Name 'Set-Clipboard' -ErrorAction SilentlyContinue) -ne $null)
{
    Set-Clipboard -Value $htmlUriWithSas
    Write-Host 'Copied the AppUri to your clipboard.' -ForegroundColor Yellow
    Write-Host ''
}
