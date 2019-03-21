# Script to check what the Azure AD Connect tool is potentially going to change as part of the initial sync of AD into an existing Office 365 tenant
# Created by Robert Milner @ Italik

<#
    PowerShell Library Change Log:
    Version     Date            Comment
    1.0.0       20/02/2019      Initial version
#>

Param (
    [Parameter( Mandatory=$false )]
    [string]$ADSearchBase
)

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
$o365Domains = Get-MsolDomain -Status Verified | Select-Object -ExpandProperty Name

# Get list of all users in local AD with a UPN:
Import-Module ActiveDirectory

if ($ADSearchBase)
{
    $ADUsers = Get-ADUser -Filter * -SearchBase $ADSearchBase
}
else
{
    $ADUsers = Get-ADUser -Filter *
}

foreach ($ADUser in $ADUsers)
{
    Write-Host "Processing user account $($ADuser.Name) ($($ADUser))" -ForegroundColor Magenta
    
    # Check if the user has a UPN assigned, and if it matches the domain in Office 365
    $userUPN = Get-ADUser $ADUser | Select-Object -ExpandProperty UserPrincipalName
    if (!$userUPN)
    {
        Write-Host "ERROR: User account $($ADuser.Name) does not have a UPN assigned within AD" -ForegroundColor Red
    }
    else
    {
        Write-Host "MATCH: User account $($ADuser.Name) has a UPN assigned: $($userUPN) within AD" -ForegroundColor Green

        # Now we need to check if the users UPN matches a verified domain within O365
        $userdomain = $userUPN.split("@",2)
        $userdomain = $userdomain[1]

        foreach ($o365Domain in $o365Domains)
        {
            if ($o365Domain -eq $userdomain)
            {
                Write-Host "MATCH: User account $($ADuser.Name) UPN ($($userdomain)) matches a verified domain ($($o365Domain)) within Office 365" -ForegroundColor Green
            }
            else
            {
                Write-Host "ERROR: User account $($ADuser.Name) does not match a verified domain within Office 365" -ForegroundColor Red
            }
        }
    }

    # Check if the user has a Proxy Address, and see if the primary Proxy Address matches the UPN
    $proxyAddresses = Get-ADUser $ADUser -properties * | Select-Object -ExpandProperty proxyAddresses
    if (!$proxyAddresses)
    {
        Write-Host "ERROR: User account $($ADuser.Name) does not have a Proxy Address assigned within AD" -ForegroundColor Red
    }
    else
    {
        $PrimarySMTP = Get-ADUser $ADUser -properties * | Select-Object -ExpandProperty proxyAddresses | Where-Object {$_ -clike "SMTP:*"}

        Write-Host "MATCH: User account $($ADuser.Name) has a proxy address assigned within AD" -ForegroundColor Green
        foreach ($proxyAddress in $proxyAddresses)
        {
            Write-Host "$($proxyAddress)" -ForegroundColor Cyan
        }

        $PrimarySMTP = $PrimarySMTP.split(":",2)
        $PrimarySMTP = $PrimarySMTP[1]
        if ($PrimarySMTP -eq $userUPN)
        {
            Write-Host "MATCH: User account $($ADuser.Name) primary SMTP address $($PrimarySMTP) matches UPN $($userUPN)" -ForegroundColor Green
        }
        else
        {
            Write-Host "ERROR: User account $($ADuser.Name) primary SMTP address $($PrimarySMTP) does not match UPN $($userUPN)" -ForegroundColor Red
        }
    }

    # Check the user in Office 365 for the UPN and check it again AD
    # Azure AD will softmatch the user against the UPN, ProxyAddresses listed in AD
    Get-AzureADUser -ObjectId $PrimarySMTP | Select-Object -ExpandProperty UserPrincipalName

    # Blank line at the bottom to split up the users as we log to the screen
    Write-Host ""
}