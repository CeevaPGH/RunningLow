###
#
# ---------------------------------------------
# RunningLow v1.2
# ---------------------------------------------
# A small Powershell script to check for low disk space and send e-mail to System Administrators
#
# by Ashley Davis (adavis@ceeva.com)
#
# originally by Darkseal/Ryadel
# https://www.ryadel.com/
#
# Licensed under GNU - General Public License, v3.0
# https://www.gnu.org/licenses/gpl-3.0.en.html
#
###


# Command-line parameters
param(
	# - minSize : the minimum free disk space acceptable threshold: any checked drive with less available space will raise a warning.
	[Parameter(Mandatory=$false,ValueFromPipelineByPropertyName=$false)]
	[string] $minSize = 20GB,

	# - hosts: If specIfied, will also check the disk space on the given colon-separated list of hostnames (machine names OR ip addresses) within the LAN.
	#            Example: $hosts = "HOSTNAME1:HOSTNAME2:129.168.0.115"
	#           IMPORTANT: Connecting to remote machines will require launching RunningLow with elevated priviledges
	#           and the Windows Management service up, running and reachable (TCP port 5985) on the remote machine.
	[Parameter(Mandatory=$false,ValueFromPipelineByPropertyName=$false)]
	[string] $hosts = $null,

	# - volumes: a colon-separated list of the drive volumes (letters) to check: set it to $null to check all local (non-network) drives.
	#            Example: $volumes = "C:D"
	[Parameter(Mandatory=$false,ValueFromPipelineByPropertyName=$false)]
	$volumes = $null,

	# - email_to : If specIfied, will send a low-disk-space warning email to the given comma-separated addresses.
	#              Example: $email_to = "my@email.com;your@email.com"
	#              Default is $null (no e-mail will be sent). Replace it with your@email.com If you don't want to set it from the CLI.
	[Parameter(Mandatory=$false,ValueFromPipelineByPropertyName=$false)]
	[string] $email_to = $null,

	# These parameters can be used to set your SMTP configuration: username, password & so on. 
	# It's strongly advisable to set them within the code instead of setting them from the CLI, as you might rarely want to change them.
	[Parameter(Mandatory=$false,ValueFromPipelineByPropertyName=$false)]
	$email_username = "username@yourdomain.com",
	[Parameter(Mandatory=$false,ValueFromPipelineByPropertyName=$false)]
	[SecureString] $email_password = (ConvertTo-SecureString "yourpassword" -AsPlainText -Force),
	[Parameter(Mandatory=$false,ValueFromPipelineByPropertyName=$false)]
	$email_smtp_host = "smtp.yourdomain.com",
	[Parameter(Mandatory=$false,ValueFromPipelineByPropertyName=$false)]
	$email_smtp_port = 25,
	[Parameter(Mandatory=$false,ValueFromPipelineByPropertyName=$false)]
	$email_from = "username@yourdomain.com",
	[Parameter(Mandatory=$false,ValueFromPipelineByPropertyName=$false)]
	$email_use_ssl = $true
)

$sep = ":"

# If there are no $cur_hosts set, set the local computer as host. 
If (!$hosts) { $hosts = $env:computername }

ForEach ($cur_host in $hosts.split($sep)) {

	$this_computer_name = $env:computername

	# converts IP to hostNames
	If (($cur_host -As [IPAddress]) -As [Bool]) {
		$cur_host = [System.Net.Dns]::GetHostEntry($cur_host).HostName
	}

	Write-Host ("`n")
	Write-Host ("----------------------------------------------")
	Write-Host ($cur_host)
	Write-Host ("----------------------------------------------")
	$drives_to_check = @()

	If ($null -eq $volumes) {
		$volArr =
			If ($cur_host -eq $this_computer_name) { Get-WMIObject win32_volume }
			Else { Invoke-Command -ComputerName $cur_host -ScriptBlock { Get-WMIObject win32_volume } }

		$drives_to_check = @()
		ForEach ($vol in $volArr | Sort-Object -Property DriveLetter) {
			If ($vol.DriveType -eq 3 -And $null -ne $vol.DriveLetter) {
				$drives_to_check += $vol.DriveLetter[0]
			}
		}
	}
	Else { $drives_to_check = $volumes.split($sep) }


	ForEach ($d in $drives_to_check) {
		Write-Host "`n  Checking drive $d ..."
		$disk = 
			If ($cur_host -eq $this_computer_name) { Get-PSDrive $d }
			Else { Invoke-Command -ComputerName $cur_host -ScriptBlock { Get-PSDrive $using:d } }

		If ($disk.Free -lt $minSize) {
			Write-Host "  - [" -noNewLine
			Write-Host "XX" -noNewLine -ForegroundColor Red
			Write-Host "] " -noNewLine
			$disk_free_bytes = $disk.Free
			$disk_free_gigs = ($disk.Free/1MB).ToString(".00")
			Write-Host "Drive $d has less than $minSize bytes free ($disk_free_bytes B - $disk_free_gigs GB)" -noNewLine

			If ($email_to) {
				Write-Host(": sending e-mail...") -noNewLine

				$email_credential = New-Object System.Management.Automation.PSCredential($email_username,$email_password)
				$message_subject =	"[RunningLow] WARNING: $cur_host drive $d has less than $minSize bytes free"
				$message_subject +=	" ($disk_free_bytes bytes - $disk_free_gigs GB)"
				$message_body =		"Hello there, `r`n`r`n"
				$message_body +=	"this is an automatic e-mail message sent by the RunningLow Powershell script "
				$message_body +=	"to inform you that $this_computer_name drive $d is running low on free space. `r`n`r`n"
				$message_body +=	"--------------------------------------------------------------"
				$message_body +=	"`r`n"
				$message_body +=	"Machine HostName: $this_computer_name `r`n"
				$message_body +=	"Machine IP Address(es): "
				$ipAddresses = Get-NetIPAddress -AddressFamily IPv4
				ForEach ($ip in $ipAddresses) {
					If ($ip.IPAddress -like "127.0.0.1") {
						continue
					}
					$message_body += $ip.IPAddress + " "
				}
				$message_body += 	"`r`n"
				$message_body += 	"Used space on drive $d : " + $disk.Used + " B. `r`n"
				$message_body += 	"Free space on drive $d : $disk_free_bytes B. `r`n"
				$message_body += 	"--------------------------------------------------------------"
				$message_body +=	"`r`n`r`n"
				$message_body += 	"This warning will fire when the free space is lower than $minSize B`r`n`r`n"
				

				$mailParam = @{
					To = $email_to.Split(";")
					From = $email_from
					Subject = $message_subject
					Body = $message_body
					SmtpServer = $email_smtp_host
					Port = $email_smtp_port
					Credential = $email_credential
					UseSsl = $email_use_ssl
				}
				try {
					Send-MailMessage @mailParam -ErrorAction Stop
				}
				catch {
					Write-Host "failed!" -ForegroundColor Red
					Write-Host "`n`t`t$_" -ForegroundColor Red
				}
			}
			Else {
				Write-Host(".")
			}
		}
		Else {
			Write-Host "  - [" -noNewLine
			Write-Host "OK" -noNewLine -ForegroundColor Green
			Write-Host "] " -noNewLine
			Write-Host "Drive $d has more than $minSize bytes free: nothing to do."
		}
	}
}
