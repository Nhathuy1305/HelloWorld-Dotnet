# 1. CONFIGURATION VARIABLES
param(
    [Parameter(Mandatory=$true, HelpMessage="Enter the password for the Service User")]
    [string]$UserPassword,

    [string]$SiteName = "EurofinsSite",    # Name of the main website in IIS
    [string]$AppName = "HelloWorld",       # Name of the sub-application
    [string]$UserName = "EurofinsServiceUser"  # Local User name
)

$HostName        = "localhost"             # The URL hostname we will bind to
$AppPoolName     = "EurofinsAppPool"       # The custom Application Pool name
$GroupName       = "EurofinsUsers"         # Local Group name
$PhysicalPath    = "C:\inetpub\wwwroot\$AppName" # Where the app files are stored
$LogPath         = "C:\inetpub\logs\EurofinsLogs" # Custom log location

# Check if the folder for the application exists. If not, create it.
# I need this folder to exist to set permissions on it later.
if (-not (Test-Path $PhysicalPath)) { 
    New-Item -Path $PhysicalPath -ItemType Directory -Force | Out-Null
    Write-Host "Created application folder at $PhysicalPath"
}

# Check if the custom log folder exists. If not, create it.
if (-not (Test-Path $LogPath)) { 
    New-Item -Path $LogPath -ItemType Directory -Force | Out-Null
    Write-Host "Created log folder at $LogPath"
}

# Import the IIS Administration Module so we can use commands like 'New-WebSite'
Import-Module WebAdministration

# 2. USER AND GROUP MANAGEMENT (Requirements: Create User, Group, Add Member)
Write-Host "--- configuring Users and Groups ---" -ForegroundColor Cyan

# Check if the Local Group exists. If not, create it.
if (-not (Get-LocalGroup -Name $GroupName -ErrorAction SilentlyContinue)) {
    New-LocalGroup -Name $GroupName
    Write-Host "Group '$GroupName' created."
}

# Convert the plain text password into a "SecureString" required by Windows security commands.
$SecurePassword = ConvertTo-SecureString $UserPassword -AsPlainText -Force

# Check if the Local User exists. If not, create it with the secure password.
if (-not (Get-LocalUser -Name $UserName -ErrorAction SilentlyContinue)) {
    New-LocalUser -Name $UserName -Password $SecurePassword -PasswordNeverExpires
    Write-Host "User '$UserName' created."
}

# Add the new User to the new Group.
Add-LocalGroupMember -Group $GroupName -Member $UserName
Write-Host "User '$UserName' added to group '$GroupName'."

# 3. FILE SYSTEM PERMISSIONS
# IIS defaults to a system account. Since we are forcing it to use our custom "$UserName",
# that user MUST have permission to read the files in C:\inetpub\wwwroot\HelloWorld.
# Without this step, I will get a "500 Internal Server Error".
Write-Host "--- Configuring File Permissions ---" -ForegroundColor Cyan

# Get the current Access Control List (ACL) of the folder
$Acl = Get-Acl $PhysicalPath

# Create a new rule: Allow "$UserName" to "ReadAndExecute"
$Ar = New-Object System.Security.AccessControl.FileSystemAccessRule($UserName, "ReadAndExecute", "ContainerInherit,ObjectInherit", "None", "Allow")

# Add this rule to the ACL and apply it back to the folder
$Acl.SetAccessRule($Ar)
Set-Acl $PhysicalPath $Acl
Write-Host "Granted 'ReadAndExecute' permission to '$UserName' on '$PhysicalPath'."

# 4. APPLICATION POOL CONFIGURATION
Write-Host "--- Configuring Application Pool ---" -ForegroundColor Cyan

# Create the Application Pool if it doesn't exist
if (-not (Test-Path "IIS:\AppPools\$AppPoolName")) {
    New-WebAppPool -Name $AppPoolName
}

# Configure the App Pool to use our custom user identity.
# By default, App Pools use "ApplicationPoolIdentity". I change this to "SpecificUser" (Type 3).
$AppPool = Get-Item "IIS:\AppPools\$AppPoolName"
$AppPool.processModel.identityType = 3 # 3 = SpecificUser
$AppPool.processModel.userName = $UserName
$AppPool.processModel.password = $UserPassword
$AppPool | Set-Item
Write-Host "App Pool '$AppPoolName' configured to run as custom user '$UserName'."

# 5. WEBSITE CREATION (Requirement: Create website, Add HTTPS binding, Modify Log)
Write-Host "--- Configuring Website ---" -ForegroundColor Cyan

# Create a temporary Self-Signed Certificate for HTTPS.
# HTTPS bindings require a certificate. Since I don't have a real one, I generate a fake one.
$Cert = New-SelfSignedCertificate -DnsName $HostName -CertStoreLocation "cert:\LocalMachine\My"
Write-Host "Created self-signed SSL certificate."

# If the website already exists (from a previous run), verify if I should delete or update it.
# For this script, we remove it to ensure a clean state.
if (Test-Path "IIS:\Sites\$SiteName") { 
    Remove-WebSite -Name $SiteName 
    Write-Host "Removed existing website to ensure clean install."
}

# Create the new Website:
# - Binds to Port 80 (HTTP) initially
# - Points to our $PhysicalPath
# - Uses the App Pool we created above
New-WebSite -Name $SiteName -Port 80 -PhysicalPath $PhysicalPath -ApplicationPool $AppPoolName

# Add the HTTPS Binding (Port 443)
New-WebBinding -Name $SiteName -Protocol https -Port 443 -SslFlags 0

# Attach the Certificate to the HTTPS binding
$Binding = Get-WebBinding -Name $SiteName -Protocol https
$Binding.AddSslCertificate($Cert.Thumbprint, "My")
Write-Host "Added HTTPS binding with SSL certificate."

# Modify the Log File Path (Requirement: Modify the path of the web site log file)
Set-ItemProperty "IIS:\Sites\$SiteName" -Name logFile.directory -Value $LogPath
Set-ItemProperty "IIS:\Sites\$SiteName" -Name logFile.period -Value "Daily"
Write-Host "Log file path updated to: $LogPath"

# 6. SUB-APPLICATION (Requirement: Create application at lower level)
Write-Host "--- Configuring Sub-Application ---" -ForegroundColor Cyan

# This creates a virtual application under the main site (e.g., localhost/HelloWorld)
# It reuses the same physical path and app pool for simplicity, satisfying the requirement.
$SubAppPath = "/$AppName"
if (-not (Get-WebApplication -Name $AppName -Site $SiteName -ErrorAction SilentlyContinue)) {
    New-WebApplication -Name $AppName -Site $SiteName -PhysicalPath $PhysicalPath -ApplicationPool $AppPoolName
    Write-Host "Sub-application '$AppName' created."
}

# COMPLETION
Write-Host "===================================================================" -ForegroundColor Green
Write-Host " DEPLOYMENT COMPLETE" -ForegroundColor Green
Write-Host "==================================================================="
Write-Host "1. Website Name:  $SiteName"
Write-Host "2. URL (HTTPS):   https://$HostName/"
Write-Host "3. Sub-App URL:   https://$HostName/$AppName"
Write-Host "4. Log Location:  $LogPath"
Write-Host "5. User Identity: $UserName"