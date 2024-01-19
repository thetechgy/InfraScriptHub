<#
.SYNOPSIS
Audits IT Glue domains against GoDaddy's active domains and reports discrepancies.

.DESCRIPTION
This script retrieves all active domains from GoDaddy and all domains from IT Glue, then compares them. 
It sends an email with a list of domains missing in IT Glue and those to be deleted from IT Glue.
This process is used as a workaround to limitations in the IT Glue API where domains can only be read, not created or updated.

.NOTES
Script Name: ITGlueDomainAudit.ps1
Version: 1.0
Author: Travis McDade
Creation Date: 2023-12-20
Last Updated: 2023-12-29
Updated By: Travis McDade

GitHub Repository: [https://github.com/thetechgy/InfraScriptHub]
Personal Website: [https://www.architechlabs.io]

References and Resources:
- GoDaddy API Documentation: [https://developer.godaddy.com]
- IT Glue API Guide: [https://api.itglue.com/developer]

Future enhancements:
- Implement secure storage for API keys and credentials, potentially using Azure Key Vault.
- Extend logging functionality to write to log file and perform log file rotation.
- Explore automation of the domain update process in IT Glue if API limitations are lifted.
#>

# ---------------------------
# IT Glue Settings
# ---------------------------
$ITGlueOrganization_Id = "YOUR_IT_GLUE_ORGANIZATION_ID_HERE"

# ---------------------------
# API Credentials
# ---------------------------
$GoDaddyApiKey = "YOUR_GODADDY_API_KEY_HERE"
$GoDaddyApiSecret = "YOUR_GODADDY_API_SECRET_HERE"
$ITGlueApiKey = "YOUR_IT_GLUE_API_KEY_HERE"

# ---------------------------
# SMTP Configuration
# ---------------------------
$SMTPServer = "YOUR_SMTP_SERVER_HERE"
$SMTPPort = "YOUR_SMTP_PORT_HERE"
$SMTPUser = "YOUR_SMTP_USER_HERE"
$SMTPPassword = "YOUR_SMTP_PASSWORD_HERE"

# ---------------------------
# Email Settings
# ---------------------------
$EmailFrom = "YOUR_EMAIL_FROM_ADDRESS_HERE"
$EmailTo = "YOUR_EMAIL_TO_ADDRESS_HERE"
$Subject = "IT Glue Domain Audit Report"

# ---------------------------
# Output Settings
# ---------------------------
$AttachmentPath = ".\Output\ITGlueMissingDomains.csv"


# Headers configuration for GoDaddy and IT Glue APIs
$GoDaddyHeaders = @{
    "Authorization" = "sso-key $($GoDaddyApiKey):$GoDaddyApiSecret"
}
$ITGlueHeaders = @{
    "x-api-key" = $ITGlueApiKey
}

# Function to send error emails
function Send-ErrorEmail {
    param (
        $ErrorMessage
    )
    # Prepare the error message body
    $Body = "An error occurred in the PowerShell script: `n`n$ErrorMessage"
    
    # Initialize SMTP client for sending the email
    $SMTPClient = New-Object Net.Mail.SmtpClient($SMTPServer, $SMTPPort)
    try {
        $SMTPClient.EnableSsl = $true
        $SMTPClient.Credentials = New-Object System.Net.NetworkCredential($SMTPUser, $SMTPPassword)
        $SMTPClient.Send($EmailFrom, $EmailTo, $Subject, $Body)
    } finally {
        $SMTPClient.Dispose()
    }
}

# Function to get active domains from GoDaddy
function Get-GoDaddyDomains {
    # Specify a high limit value, adjust as needed
    $limit = 1000
    $GoDaddyDomainEndpoint = "https://api.godaddy.com/v1/domains?statuses=ACTIVE&limit=$limit"

    try {
        # Making API call to GoDaddy to fetch domains
        $godaddyDomains = Invoke-RestMethod -Uri $GoDaddyDomainEndpoint -Method Get -Headers $GoDaddyHeaders
        return $godaddyDomains | Select-Object -ExpandProperty domain
    } catch {
        Send-ErrorEmail -ErrorMessage $_.Exception.Message
        throw
    }
}

# Function to get domains from IT Glue
function Get-ITGlueDomains {
    $ITGlueDomainEndpoint = "https://api.itglue.com/organizations/$($ITGlueOrganization_Id)/relationships/domains?page[size]=1000"
    try {
        # Making API call to IT Glue to fetch domains
        $itGlueDomains = Invoke-RestMethod -Uri $ITGlueDomainEndpoint -Method Get -Headers $ITGlueHeaders
        return $itGlueDomains.data | ForEach-Object { $_.attributes.name }
    } catch {
        Send-ErrorEmail -ErrorMessage $_.Exception.Message
        throw
    }
}

# Function to send email with attachment if necessary
function Send-EmailWithAttachment {
    param (
        $DomainsToImport,
        $DomainsToDelete
    )

    # Constructing the HTML email body
    $Body = @"
    <html>
    <body>
    <h2>Automated Domain Management Report</h2>
    <p>This report compares domain records between GoDaddy and IT Glue. It identifies domains that need to be updated in IT Glue.</p>
    <br>
    <table>
"@

    # Handle domains to be imported
    if ($DomainsToImport) {
        $Body += "<tr><td>"
        $Body += "<p><strong>Domains to be manually imported to IT Glue:</strong></p>"
        $Body += "<p>Import the attached csv into the IT Glue Domains Core Asset for the Organization to add the missing domains.</p>"
        $Body += "<ul>"
        foreach ($domain in $DomainsToImport) {
            $Body += "<li>$domain</li>"
        }
        $Body += "</ul>"
        $Body += "</td></tr>"

        # Prepare data for CSV with additional fields
        $csvData = $DomainsToImport | ForEach-Object {
            [PSCustomObject]@{
                id = ""
                name = $_
                registrar_name = ""
                expires_on = ""
                updated_at = ""
                notes = "Imported from IT Glue Domain Audit Script"
            }
        }
        # Export to CSV
        $csvData | Export-Csv -Path $AttachmentPath -NoTypeInformation
    } else {
        $Body += "<tr><td><p>No new domains to import to IT Glue.</p></td></tr>"
    }

    # Handle domains to be deleted, or mention 'none' if there are no domains to delete
    $Body += "<tr><td>"
    $Body += "<p><strong>Domains suggested for manual deletion from IT Glue:</strong></p>"
    $Body += "<ul>"
    if ($DomainsToDelete) {
        foreach ($domain in $DomainsToDelete) {
            $Body += "<li>$domain</li>"
        }
    } else {
        $Body += "<li>None</li>"
    }
    $Body += "</ul>"
    $Body += "</td></tr>"
    $Body += "</table>"

    # Add execution details
    $Hostname = [System.Net.Dns]::GetHostName()
    $date = Get-Date -Format "MM-dd-yyyy"
    $time = Get-Date -Format "HH:mm:ss"
    $TimeZone = [System.TimeZoneInfo]::Local.StandardName
    $Body += "<hr>"
    $Body += "<p style='font-style: italic; color: gray;'>This report was automatically generated by the <b>ITGlueDomainAudit.ps1</b> script, executed as a scheduled task.</p>"
    $Body += "<p style='font-style: italic; color: gray;'><b>Execution Details:</b><br>"
    $Body += "Hostname: <b>$Hostname</b> | Date: <b>$date</b> | Time: <b>$time $TimeZone</b><br>"

    $Body += @"
    </body>
    </html>
"@

    # Send email only if necessary
    if ($DomainsToImport -or $DomainsToDelete) {
        $SMTPClient = New-Object Net.Mail.SmtpClient($SMTPServer, $SMTPPort)
        try {
            $SMTPClient.EnableSsl = $true
            $SMTPClient.Credentials = New-Object System.Net.NetworkCredential($SMTPUser, $SMTPPassword)
            $MailMessage = New-Object System.Net.Mail.MailMessage($EmailFrom, $EmailTo, $Subject, $Body)
            $MailMessage.IsBodyHtml = $true
            
            # Attach CSV file if it exists and there are domains to import
            if ($DomainsToImport -and (Test-Path $AttachmentPath)) {
                $Attachment = New-Object System.Net.Mail.Attachment($AttachmentPath)
                $MailMessage.Attachments.Add($Attachment)
            }
            
            $SMTPClient.Send($MailMessage)
        } finally {
            $SMTPClient.Dispose()
        }
    }
}

# Main script execution
try {
    # Fetching domains from GoDaddy and IT Glue
    $godaddyDomains = Get-GoDaddyDomains
    $itglueDomains = Get-ITGlueDomains

    # Determining domains to add or delete
    $domainsToAdd = $godaddyDomains | Where-Object { $_ -notin $itglueDomains }
    $domainsToDelete = $itglueDomains | Where-Object { $_ -notin $godaddyDomains }

    # Send report if there are changes
    if ($domainsToAdd -or $domainsToDelete) {
        Send-EmailWithAttachment -DomainsToImport $domainsToAdd -DomainsToDelete $domainsToDelete
    }
} catch {
    # Handling any unexpected errors
    $ErrorMessage = $_.Exception.Message
    Send-ErrorEmail -ErrorMessage $ErrorMessage
    Write-Error "An error occurred: $ErrorMessage"
}
