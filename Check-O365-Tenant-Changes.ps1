# Script to check what the Azure AD Connect tool is potentially going to change as part of the initial sync of AD into an existing Office 365 tenant
# Created by Robert Milner @ Italik

<#
    PowerShell Library Change Log:
    Version     Date            Comment
    1.0.0       20/02/2019      Initial version
#>

# LOGGING TO THE SCREEN AND TO FILE

if (!(Test-Path -Path "C:\Temp"))
{
    New-Item -Path "C:\Temp" -ItemType container
}
$appLogName = $ApplicationName -replace " ","_"
Start-Transcript -Path "C:\Temp\O365 Tennant Log.txt" -Append

function LogScreen()
{
    param ([string]$logstring)
    $DateTime = (Get-Date).ToString('yyyyMMdd HH:mm:ss')
    $content = "$DateTime : $logstring"
    Write-Host $content
}

$currDir = Convert-Path -Path .
LogScreen "Working Directory: $($currDir)"

# Connect to Office 365
# Get list of domains
$o365Domains = Get-MsolDomain -Status Verified

# Get list of all users in local AD with a UPN:
Import-Module ActiveDirectory
$ADUsers = Get-ADUser -Filter * -SearchBase "OU=Highfield,OU=Staff,DC=HIGHBROOK,DC=local"

foreach ($ADUser in $ADUsers)
{
    $userUPN = Get-ADUser $ADUser -Properties UserPrincipalName | Select-Object -Expand UserPrincipalName
    if (!$UPNUser)
    {
        LogScreen "ERROR: $($ADUser) does not have a UPN assigned"
    }
    else
    {
        LogScreen "$($UPNUser) has a UPN assigned: $($userUPN)"

        # Now we need to check if the users UPN matches a verified domain within O365
        $userdomain = $userUPN.split("@",2)
        $userdomain = $userdomain[1]

        foreach ($o365Domain in $o365Domains)
        {
            if ($o365Domain -eq $userdomain)
            {
                LogScreen "MATCH: User UPN matches a verified domain within Office 365"
            }
            else
            {
                LogScreen "ERROR: User UPN does not match a verified domain within Office 365"    
            }
        }
    }
    $proxyAddresses = Get-ADUser $ADUser -Properties proxyAddresses | Select-Object -Expand proxyAddresses
    if (!$proxyAddresses)
    {
        LogScreen "ERROR: $($ADUser) does not have a Proxy Address assigned"
    }
    else
    {
        $PrimarySMTP = Get-ADUser $user -Properties proxyAddresses | Select-Object -Expand proxyAddresses | Where-Object {$_ -clike "SMTP:*"}

        LogScreen "$($ADUser) has a Proxy Address assigned"
        foreach ($proxyAddress in $proxyAddresses)
        {
            LogScreen "$($proxyAddress)"
        }

        if (!($PrimarySMTP -eq $userUPN))
        {
            LogScreen "ERROR: Users primary SMTP address $($PrimarySMTP) does not match UPN $($userUPN)"
        }
    }
}