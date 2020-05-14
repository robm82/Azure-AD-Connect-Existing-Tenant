<#
    Script to check if the users within local AD have been setup correctly before the initial sync with Office 365 that already has existing users.
    This is to ensure that there are no potential issues before the sync.
    Created by Robert Milner at Italik.
#>


<#
    PowerShell Library Change Log:
    Version     Date            Comment
    1.0.0       20/02/2019      Initial version
#>

Param (
    [Parameter( Mandatory=$false )]
    [string]$ADSearchBase,

    [Parameter( Mandatory=$true )]
    [string]$UserName
)

# LOGGING TO THE SCREEN AND TO FILE

if (!(Test-Path -Path "C:\Temp"))
{
    New-Item -Path "C:\Temp" -ItemType container
}
Start-Transcript -Path "C:\Temp\O365 Tennant Log.txt" -Append


# Check to see if all the required PowerShell module exists

$ExchangeMFAModule = 'Microsoft.Exchange.Management.ExoPowershellModule'
$ModuleList = @(Get-ChildItem -Path "$($env:LOCALAPPDATA)\Apps\2.0" -Filter "$($ExchangeMFAModule).manifest" -Recurse ) | Sort-Object LastWriteTime -Desc | Select-Object -First 1
If ( $ModuleList)
{
    $ModuleName = Join-path -Path $ModuleList[0].Directory.FullName -ChildPath "$($ExchangeMFAModule).dll"
}

if (Get-Module -ListAvailable -FullyQualifiedName $ModuleName)
{
    Write-Host "SUCCESS: Found Exchange Online PowerShell Module" -ForegroundColor Green
    Import-Module -FullyQualifiedName $ModuleName -Force
    New-EXOPSSession -ConnectionUri https://outlook.office365.com/powershell-liveid/ -userprincipalname $UserName
} else
{
    Write-Host "ERROR: Could not find Exchange Online PowerShell Module - please install" -ForegroundColor Red
    Start-Process -FilePath http://bit.ly/ExOPSModule
    Exit
}

if (Get-Module -ListAvailable -Name "AzureAD")
{
    Write-Host "SUCCESS: Found Azure AD PowerShell Module" -ForegroundColor Green
    Import-Module -Name AzureAD -Force
    Connect-AzureAD -AccountId $UserName
} else
{
    Write-Host "ERROR: Could not find Azure AD PowerShell Module - please install" -ForegroundColor Red
    Start-Process -FilePath https://www.powershellgallery.com/packages/AzureAD
    Exit
}

if (Get-Module -ListAvailable -Name "MSOnline")
{
    Write-Host "SUCCESS: Found MSOnline Module" -ForegroundColor Green
    Import-Module -Name MSOnline -Force
    Connect-MsolService
} else
{
    Write-Host "ERROR: Could not find Azure AD PowerShell Module - please install" -ForegroundColor Red
    Start-Process -FilePath https://www.powershellgallery.com/packages/MSOnline
    Exit
}

if (Get-Module -ListAvailable -Name "ActiveDirectory")
{
    Write-Host "SUCCESS: Found ActiveDirectory Module" -ForegroundColor Green
    Import-Module -Name ActiveDirectory -Force
} else
{
    Write-Host "ERROR: Could not find ActiveDirectory Module" -ForegroundColor Red
    Exit
}

# Connect to Office 365
# Get list of domains
$o365Domains = Get-MsolDomain -Status Verified
$o365Domains = $o365Domains.Name -notmatch "onmicrosoft.com"

foreach ($o365Domain in $o365Domains)
{
    Write-Host "INFO: Processing O365 domains; $($O365Domain)" -ForegroundColor Cyan
}
Write-Host ""

# Get list of all users in local AD with a UPN:
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
            Write-Host "INFO: Proxy Address; $($proxyAddress)" -ForegroundColor Cyan
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

    try
    {
        $AzureADUserUPN = Get-AzureADUser -ObjectId $userUPN | Select-Object -ExpandProperty UserPrincipalName
    }
    catch
    {
        Write-Host "WARNING: User account $($ADuser.Name) UPN ($($userUPN)) cannot be matched against an Office 365 UPN" -ForegroundColor Yellow
    }

    try
    {
        $AzureADUserProxy = Get-AzureADUser -ObjectId $PrimarySMTP -ErrorAction SilentlyContinue | Select-Object -ExpandProperty UserPrincipalName
    }
    catch
    {
        Write-Host "WARNING: User account $($ADuser.Name) Proxy Address ($($PrimarySMTP)) cannot be matched against an Office 365 UPN" -ForegroundColor Yellow
    }

    if ($AzureADUserUPN)
    {
        Write-Host "MATCH: User account $($ADuser.Name) with the AD UPN of $($userUPN) matches the UPN in Office 365 $($AzureADUserUPN)" -ForegroundColor Green
        Write-Host "INFO: Account will softmatch as part of the initial sync" -ForegroundColor Cyan
    }
    elseif ($AzureADUserProxy)
    {
        Write-Host "MATCH: User account $($ADuser.Name) with the Proxy Address $($PrimarySMTP) matches the UPN in Office 365 $($AzureADUserProxy)" -ForegroundColor Green
        Write-Host "INFO: Account will softmatch as part of the initial sync" -ForegroundColor Cyan
    }

    if (!($AzureADUserUPN) -and !($AzureADUserProxy))
    {
        Write-Host "WARNING: User account $($ADuser.Name) cannot be found within Office 365 (a new object with be created)" -ForegroundColor Yellow
    }

    # Blank line at the bottom to split up the users as we log to the screen
    Write-Host ""

    # Cleanup variables
    Clear-Variable -Name "PrimarySMTP" -ErrorAction SilentlyContinue
    Clear-Variable -Name "userUPN" -ErrorAction SilentlyContinue
    Clear-Variable -Name "proxyAddresses" -ErrorAction SilentlyContinue
    Clear-Variable -Name "AzureADUserUPN" -ErrorAction SilentlyContinue
    Clear-Variable -Name "AzureADUserProxy" -ErrorAction SilentlyContinue
}

Write-Host "Make sure to now run IDFix to ensure that there are no further issues"