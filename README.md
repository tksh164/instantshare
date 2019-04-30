# InstantShare

## About this tool
This tool setup simple chat environment on Azure.

![InstantShare](image/instantshare1.png)

## Prerequisites
- PowerShell
    - PowerShell 5.x and [PowerShell Core 6.x](https://github.com/PowerShell/PowerShell) are supported.
- [Azure PowerShell (Az module)](https://docs.microsoft.com/en-us/powershell/azure/install-az-ps)
- Azure subscription
    - The setup script creates a resource group and a storage account in your Azure subscription. You need enough permission against the subscription.

## How to use this tool

InstantShare setup is complete in a minute. It is super easy.

```
PS > .\setup.ps1
...

AppUri : https://instantshare20005242.blob.core.windows.net/instantshare/index.html?sv=2018-03-28&sr=b&si=CInstantShare&sig=tNj1Hg%2Fh7OajibJvH2ZxixvifIBvpJwhg8bh0HMUW8M%3D

Copied the AppUri to your clipboard.
```
