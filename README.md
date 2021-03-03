# InstantShare

InstantShare provides an information sharing space in instantly. For example, share information from trainer to audience in the lightweight classroom workshop, also share information with each other.

InstantShare uses just a storage account in Azure that meaning the cost is very low (almost zero).

![InstantShare](image/instantshare1.png)

## Prerequisites

- PowerShell
    - PowerShell 5.x and [PowerShell Core 6.x](https://github.com/PowerShell/PowerShell) are supported.
- [Azure PowerShell (Az module)](https://docs.microsoft.com/en-us/powershell/azure/install-az-ps)
- Azure subscription
    - The setup script creates a resource group and a storage account in your Azure subscription. You need enough permission against the subscription.

## Deployment

The setup is super easy and complete in a minute.

1. [Download the zip file](https://github.com/tksh164/InstantShare/archive/master.zip) from GitHub (this page).

2. Unblock the downloaded zip file and expand it.

    ```
    PS > Unblock-File -Path .\InstantShare-master.zip
    PS > Expand-Archive -Path .\InstantShare-master.zip -DestinationPath .\InstantShare-master
    ```

3. Sign-in to Azure if not yet it. InstantShare will be deployed on that subscription.

    ```
    PS > Connect-AzAccount
    ```

4. Run the setup script.

    ```
    PS > cd .\InstantShare-master\InstantShare-master
    PS > .\setup.ps1 -Verbose
    ```

5. Open the InstantShare URL.

    ```
    AppUri : https://instantshare10215101.blob.core.windows.net/instantshare/index.html?sv=2017-07-29&sr=b&si=CInstantShare&sig=Jttr%2FLxb6W82y4sTei%2FTNSvSssUK4vIDJAwAX6PpMZM%3D
    ```

## Be careful

- We do not recommend share any secrets (e.g. password) on InstantShare. Because InstantShare does not have authentication and authorization features. This meaning anonymous users are can access if they know the URL of InstantShare.

## Tips

- You can change the accessible period from the access policy settings on the InstantShare container within the storage account in Azure portal.
- InstantShare does not have the edit/delete features. But you can do it from [Azure Storage Explorer](https://azure.microsoft.com/en-us/features/storage-explorer/) or Azure Storage Explorer in Azure portal.
- You can customize the appearance by edit index.html file and re-upload it.
- We recommend that use InstantShare with URL shortening services because InstantShare's URL is long.

## License

Copyright (c) 2018-present Takeshi Katano. All rights reserved. This software is released under the [MIT License](https://github.com/tksh164/InstantShare/blob/master/LICENSE).
