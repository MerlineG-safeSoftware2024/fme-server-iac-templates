param(
 [string] $externalhostname,
 [string] $databasehostname,
 [string] $databaseUsername,
 [string] $databasePassword,
 [string] $storageAccountName,
 [string] $storageAccountKey
)

try {
    # try on Azure first
    $private_ip = Invoke-RestMethod -Uri "http://169.254.169.254/metadata/instance/network/interface/0/ipv4/ipAddress/0/privateIpAddress?api-version=2017-08-01&format=text"  -Headers @{"Metadata"="true"}
    # get the first part of the database hostname to use with the username
    $hostShort,$rest = $databaseHostname -split '\.',2
    # update variables for Azure
    $storageUserName = "Azure\$storageAccountName"
    $storageAccountName = "$storageAccountName.file.core.windows.net"
    $storageAccountPath = "$storageAccountName\fmeflowdata"
    $aws = $false
}
catch {
    # if that doesn't work we must be on AWS
    $private_ip = Invoke-RestMethod -Uri "http://169.254.169.254/latest/meta-data/local-ipv4"  -Headers @{"Metadata"="true"}
    # update variables for AWS
    $storageUserName = "Admin"
    $storageAccountPath = "$storageAccountName\share"
    $aws = $true
}
$fmeDatabaseUsername = "fmeflow"
$default_values = "C:\Program Files\FMEFlow\Config\values.yml"
$modified_values = "C:\Program Files\FMEFlow\Config\values-modified.yml"

# write out yaml file with modified data
Remove-Item "$modified_values"
Add-Content "$modified_values" "repositoryserverrootdir: `"Z:/fmeflowdata`"" 
Add-Content "$modified_values" "hostname: `"${private_ip}`""
Add-Content "$modified_values" "nodename: `"${private_ip}`""
Add-Content "$modified_values" "corehostname: `"${private_ip}`""
Add-Content "$modified_values" "externalhostname: `"${externalhostname}`""
Add-Content "$modified_values" "memuraihosts: `"${private_ip}`""
Add-Content "$modified_values" "servletport: `"8080`""
Add-Content "$modified_values" "pgsqlhostname: `"${databasehostname}`""
Add-Content "$modified_values" "pgsqlport: `"5432`""
Add-Content "$modified_values" "pgsqlpassword: `"fmeflow`""
Add-Content "$modified_values" "pgsqlpasswordescaped: `"fmeflow`""
Add-Content "$modified_values" "pgsqlconnectionstring: `"jdbc:postgresql://${databasehostname}:5432/fmeflow`""
Add-Content "$modified_values" "externalport: `"80`""
Add-Content "$modified_values" "logprefix: `"${private_ip}_`""
Add-Content "$modified_values" "postgresrootpassword: `"postgres`""
Add-Content "$modified_values" "redisdirforwardslash: `"C:/REDISDIR/`""
Add-Content "$modified_values" "enableregistrationresponsetransactionhost: `"true`""
New-Item -Path "C:\" -Name "REDISDIR" -ItemType "directory"

# replace blanked out values to ensure confd runs correctly
((Get-Content -path "$default_values" -Raw) -replace '<<DATABASE_PASSWORD>>','"fmeflow"') | Set-Content -Path "$default_values"
((Get-Content -path "$default_values" -Raw) -replace '<<POSTGRES_ROOT_PASSWORD>>','"postgres"') | Set-Content -Path "$default_values"

$ErrorActionPreference = 'SilentlyContinue'
Push-Location -Path "C:\Program Files\FMEFlow\Config\confd"
& "C:\Program Files\FMEFlow\Config\confd\confd.exe" -confdir "C:\Program Files\FMEFlow\Config\confd" -backend file -file "$default_values" -file "$modified_values" -onetime
Pop-Location

# add ssl mode to jdbc connection string and set username to include hostname
(Get-Content "C:\Program Files\FMEFlow\Server\fmeDatabaseConfig.txt") `
    -replace '5432/fmeflow', '5432/fmeflow?sslmode=require' `
    -replace "DB_USERNAME=fmeflow","DB_USERNAME=$fmeDatabaseUsername" |
  Out-File "C:\Program Files\FMEFlow\Server\fmeDatabaseConfig.txt.updated"
Move-Item -Path "C:\Program Files\FMEFlow\Server\fmeDatabaseConfig.txt.updated" -Destination "C:\Program Files\FMEFlow\Server\fmeDatabaseConfig.txt" -Force
((Get-Content "C:\Program Files\FMEFlow\Server\fmeDatabaseConfig.txt") -join "`n") + "`n" | Set-Content -NoNewline "C:\Program Files\FMEFlow\Server\fmeDatabaseConfig.txt"

(Get-Content "C:\Program Files\FMEFlow\Server\fmeFlowWebApplicationConfig.txt") `
    -replace '5432/fmeflow', '5432/fmeflow?sslmode=require' `
    -replace 'DB_USERNAME=fmeflow',"DB_USERNAME=$fmeDatabaseUsername" |
  Out-File "C:\Program Files\FMEFlow\Server\fmeFlowWebApplicationConfig.txt.updated"
Move-Item -Path "C:\Program Files\FMEFlow\Server\fmeFlowWebApplicationConfig.txt.updated" -Destination "C:\Program Files\FMEFlow\Server\fmeFlowWebApplicationConfig.txt" -Force
((Get-Content "C:\Program Files\FMEFlow\Server\fmeFlowWebApplicationConfig.txt") -join "`n") + "`n" | Set-Content -NoNewline "C:\Program Files\FMEFlow\Server\fmeFlowWebApplicationConfig.txt"

# connect to the azure file share
$connectTestResult = Test-NetConnection -ComputerName $storageAccountName -Port 445
if ($connectTestResult.TcpTestSucceeded) {
    # Save the password so the drive will persist on reboot
    $username = $storageUserName
    $password = ConvertTo-SecureString "$storageAccountKey" -AsPlainText -Force
    $cred = New-Object System.Management.Automation.PSCredential -ArgumentList ($username, $password)

    # Mount the drive
    New-SmbGlobalMapping -RemotePath "\\$storageAccountPath" -Credential $cred -LocalPath Z: -FullAccess @("NT AUTHORITY\SYSTEM", "NT AUTHORITY\NetworkService") -Persistent $True

} else {
    Write-Error -Message "Unable to reach the Azure storage account via port 445. Check to make sure your organization or ISP is not blocking port 445, or use Azure P2S VPN, Azure S2S VPN, or Express Route to tunnel SMB traffic over a different port."
}

if ( !(Test-Path -Path 'Z:\fmeflowdata\localization' -PathType Container) ) {
    New-Item -Path 'Z:\fmeflowdata' -ItemType Directory
    Copy-Item 'C:\Data\*' -Destination 'Z:\fmeflowdata' -Recurse
}

# Wait until database is available before writing the schema
do {
    Write-Host "Waiting until Database is up..."
    Start-Sleep 1
    & "C:\Program Files\FMEFlow\Utilities\pgsql\bin\pg_isready.exe" -h ${databasehostname} -p 5432
    $databaseReady = $?
    Write-Host $databaseReady
} until ($databaseReady)
$env:PGPASSWORD = "fmeflow"
$schemaExists = & "C:\Program Files\FMEFlow\Utilities\pgsql\bin\psql.exe" -h ${databasehostname} -d fmeflow -p 5432 -c "SELECT EXISTS(SELECT * FROM information_schema.tables WHERE table_name = 'fme_config_props')" -w -t -U $fmeDatabaseUsername 2>&1
if($schemaExists -like "*t*") {
    Write-Host "The schema already exists"
}
else {
    $env:PGPASSWORD = $databasePassword

    & "C:\Program Files\FMEFlow\Utilities\pgsql\bin\psql.exe" -d postgres -h $databasehostname -U $databaseUsername -p 5432 -f "C:\Program Files\FMEFlow\Server\database\postgresql\postgresql_createUser.sql" >"C:\Program Files\FMEFlow\resources\logs\installation\CreateUser.log" 2>&1
    & "C:\Program Files\FMEFlow\Utilities\pgsql\bin\psql.exe" -d postgres -h $databasehostname -U $databaseUsername -p 5432 -f "C:\Program Files\FMEFlow\Server\database\postgresql\postgresql_createDB.sql" >"C:\Program Files\FMEFlow\resources\logs\installation\CreateDatabase.log" 2>&1

    $env:PGPASSWORD = "fmeflow"
    & "C:\Program Files\FMEFlow\Utilities\pgsql\bin\psql.exe" -d fmeflow -h $databasehostname -U $fmeDatabaseUsername -p 5432 -f "C:\Program Files\FMEFlow\Server\database\postgresql\postgresql_createSchema.sql" >"C:\Program Files\FMEFlow\resources\logs\installation\CreateSchema.log" 2>&1
}

# create a script with the account name and password written into it to use at startup
Write-Output "`$username = `"$storageUserName`"" | Out-File -FilePath "C:\startup.ps1"
Write-Output "`$password = ConvertTo-SecureString `"$storageAccountKey`" -AsPlainText -Force" | Out-File -FilePath "C:\startup.ps1" -Append
Write-Output "`$cred = New-Object System.Management.Automation.PSCredential -ArgumentList (`$username, `$password)" | Out-File -FilePath "C:\startup.ps1" -Append
Write-Output "New-SmbGlobalMapping -RemotePath `"\\$storageAccountPath`" -Credential `$cred -LocalPath Z: -FullAccess @(`"NT AUTHORITY\SYSTEM`", `"NT AUTHORITY\NetworkService`") -Persistent `$True" | Out-File -FilePath "C:\startup.ps1" -Append
Write-Output "Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled False" | Out-File -FilePath "C:\startup.ps1" -Append

# create a scheduled task to run the above script at startup
$action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument '-File "C:\startup.ps1"'
$trigger = New-ScheduledTaskTrigger -AtStartup
$principal = New-ScheduledTaskPrincipal -UserId SYSTEM -LogonType ServiceAccount -RunLevel Highest
$definition = New-ScheduledTask -Action $action -Principal $principal -Trigger $trigger -Description "Mount Azure files at startup"
Register-ScheduledTask -TaskName "AzureMountFiles" -InputObject $definition

Set-Service -Name "FME Flow Core" -StartupType "Automatic"
Set-Service -Name "FMEFlowAppServer" -StartupType "Automatic"
Start-Service -Name "FME Flow Core"
Start-Service -Name "FMEFlowAppServer"

Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled False

# remove coreInit task on AWS only
if ($aws) {
    Unregister-ScheduledTask -TaskName "coreInit" -Confirm:$false
}
