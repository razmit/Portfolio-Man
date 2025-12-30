# Get status of VPN Service (Running or Stopped)
$statusVPNService = (Get-Service -Name "Pan*").Status

# Get current hour (24-hour format)
$currentTimeHour = Get-Date -Format HH:mm

# Array of morning hours
$activationHours = @("8", "9", "10", "11")

# Array of afternoon hours
$deactivationHours = @("16:00","16:30", "17:00")

Add-Type -AssemblyName PresentationCore,PresentationFramework 
$ButtonType = [System.Windows.MessageBoxButton]::YesNo 
$MessageIcon = [System.Windows.MessageBoxImage]::Error 
$MessageBody = "Are you sure you want to delete the log file?" 
$MessageTitle = "Confirm Deletion"

$Result = [System.Windows.MessageBox]::Show($MessageBody,$MessageTitle,$ButtonType,$MessageIcon)

Write-Host "Your choice is $Result" 

# Verify if the service is Running or Stopped
if ($statusVPNService = "Running") {
    Write-Output "The VPN is running holy shit"
    Write-Output $currentTimeHour.Substring(0,2)
    if ($currentTimeHour.Substring(0,2) -in $deactivationHours) {
        Write-Output "Watafaaaaaaaaaak"
    } 
    
} elseif ($statusVPNService = "Stopped") {
    Write-Output "The VPN is stopped holy shit"
} else {
    Write-Output "We're fucked holy shit. It's not running nor stopped."
}



if ($currentTimeHour -in $deactivationHours) {
    
}


# THIS IS A TEST CHANGE I WANT TO SEE IF IT WORKS