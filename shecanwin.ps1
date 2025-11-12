# Shecan DNS Manager - Windows Installer
# Run once as Administrator

if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Error: Please run PowerShell as Administrator" -ForegroundColor Red
    exit 1
}

Write-Host "Shecan DNS Manager - Windows Setup"
Write-Host "=================================="

$installPath = "$env:ProgramFiles\Shecan"
if (-not (Test-Path $installPath)) {
    New-Item -ItemType Directory -Path $installPath -Force | Out-Null
}

Write-Host ""
Write-Host "Select your Shecan plan:"
Write-Host "1) FREE User (178.22.122.100, 185.51.200.2)"
Write-Host "2) PREMIUM User (178.22.122.101, 185.51.200.1 + DDNS)"
$choice = Read-Host "Enter choice (1 or 2)"

$mode = ""
$dns1 = ""
$dns2 = ""
$ddnsPassword = ""

switch ($choice) {
    "1" {
        $mode = "free"
        $dns1 = "178.22.122.100"
        $dns2 = "185.51.200.2"
    }
    "2" {
        $mode = "premium"
        $dns1 = "178.22.122.101"
        $dns2 = "185.51.200.1"
        
        Write-Host ""
        Write-Host "Enter your Shecan DDNS Password Token:"
        Write-Host "Only the token part (not the full URL)"
        Write-Host ""
        Write-Host "Example:"
        Write-Host "If your URL is: https://ddns.shecan.ir/update?password=bfdf57e82c9d6"
        Write-Host "Then enter only: bfdf57e82c9d6"
        Write-Host ""
        $ddnsPassword = Read-Host "Password Token"
        
        if ($ddnsPassword -like "*password=*") {
            $ddnsPassword = $ddnsPassword -replace '.*password=', '' -replace '[^a-zA-Z0-9].*', ''
        }
        
        if ([string]::IsNullOrWhiteSpace($ddnsPassword)) {
            Write-Host "Error: Password token required for premium users" -ForegroundColor Red
            exit 1
        }
    }
    default {
        Write-Host "Error: Invalid choice" -ForegroundColor Red
        exit 1
    }
}

$command = @'
function global:shecan {
    param([Parameter(Position=0)][string]$Action)

    $config = Get-Content "$env:ProgramFiles\Shecan\config.json" | ConvertFrom-Json
    $mode = $config.Mode
    $dns1 = $config.Dns1
    $dns2 = $config.Dns2
    $ddnsPassword = $config.DdnsPassword

    if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Host "Error: Please run with Administrator privileges" -ForegroundColor Red
        return
    }

    function Get-ActiveAdapter {
        Get-NetAdapter | Where-Object { $_.Status -eq "Up" -and $_.Name -notlike "*Bluetooth*" -and $_.Name -notlike "*Loopback*" } | Select-Object -First 1
    }

    function Test-DnsServers {
        try {
            nslookup google.com $dns1 2>$null | Out-Null
            return 0, $dns1, $dns2
        } catch {
            try {
                nslookup google.com $dns2 2>$null | Out-Null
                return 1, $dns2, "8.8.8.8"
            } catch {
                return 2, "8.8.8.8", "8.8.4.4"
            }
        }
    }

    switch ($Action.ToLower()) {
        "start" {
            $adapter = Get-ActiveAdapter
            if (-not $adapter) {
                Write-Host "Error: No active network adapter found" -ForegroundColor Red
                return
            }

            Write-Host "Flushing DNS cache before testing..."
            Clear-DnsClientCache

            $status, $currentDns1, $currentDns2 = Test-DnsServers
            Write-Host "Applying DNS to: $($adapter.Name)"
            Write-Host "Using DNS servers: $currentDns1, $currentDns2"
            
            Set-DnsClientServerAddress -InterfaceAlias $adapter.Name -ServerAddresses $currentDns1, $currentDns2

            if ($mode -eq "premium") {
                $taskName = "ShecanDDNS"
                $taskExists = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
                if (-not $taskExists) {
                    $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-Command `"curl https://ddns.shecan.ir/update?password=$ddnsPassword`""
                    $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Minutes 5)
                    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
                    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -User "SYSTEM" -Force | Out-Null
                }
                Start-ScheduledTask -TaskName $taskName
                Write-Host "DDNS auto-updates enabled (every 5 minutes)" -ForegroundColor Green
            }

            Write-Host "Flushing DNS cache after applying..."
            Clear-DnsClientCache
            ipconfig /flushdns | Out-Null
            
            Write-Host ""
            Write-Host "Shecan DNS ACTIVATED" -ForegroundColor Green
            Write-Host "Mode: $mode"
            Write-Host "Active DNS: $currentDns1, $currentDns2"
            
            if ($status -eq 1) {
                Write-Host "Note: Using secondary DNS + Google fallback (primary DNS unavailable)" -ForegroundColor Yellow
            } elseif ($status -eq 2) {
                Write-Host "Note: Using Google DNS fallback (both Shecan DNS unavailable)" -ForegroundColor Yellow
            }
        }
        "stop" {
            $adapter = Get-ActiveAdapter
            if (-not $adapter) {
                Write-Host "Error: No active network adapter found" -ForegroundColor Red
                return
            }

            Write-Host "Removing Shecan DNS from: $($adapter.Name)"
            
            if ($mode -eq "premium") {
                Stop-ScheduledTask -TaskName "ShecanDDNS" -ErrorAction SilentlyContinue
                Disable-ScheduledTask -TaskName "ShecanDDNS" -ErrorAction SilentlyContinue
            }

            Set-DnsClientServerAddress -InterfaceAlias $adapter.Name -ResetServerAddresses
            
            Write-Host "Flushing DNS cache..."
            Clear-DnsClientCache
            ipconfig /flushdns | Out-Null
            
            Write-Host "Shecan DNS DEACTIVATED" -ForegroundColor Green
        }
        "status" {
            Write-Host "Shecan Status:"
            Write-Host "  Mode: $mode"
            Write-Host "  Primary DNS: $dns1"
            Write-Host "  Secondary DNS: $dns2"
            Write-Host "  Fallback: Google DNS (8.8.8.8, 8.8.4.4)"
            Write-Host ""
            
            $adapter = Get-ActiveAdapter
            if ($adapter) {
                Write-Host "Current Network DNS for '$($adapter.Name)':"
                $dnsServers = Get-DnsClientServerAddress -InterfaceAlias $adapter.Name -AddressFamily IPv4 | Select-Object -ExpandProperty ServerAddresses
                if ($dnsServers) {
                    $dnsServers | ForEach-Object { Write-Host "  $_" }
                } else {
                    Write-Host "  (Using DHCP)"
                }
            }

            if ($mode -eq "premium") {
                Write-Host ""
                $task = Get-ScheduledTask -TaskName "ShecanDDNS" -ErrorAction SilentlyContinue
                if ($task -and $task.State -eq "Ready") {
                    Write-Host "DDNS Service: ACTIVE (updates every 5 minutes)" -ForegroundColor Green
                } else {
                    Write-Host "DDNS Service: INACTIVE" -ForegroundColor Yellow
                }
            }
        }
        "test" {
            Write-Host "Flushing DNS cache before testing..."
            Clear-DnsClientCache
            
            Write-Host "Testing DNS connectivity..."
            $status, $currentDns1, $currentDns2 = Test-DnsServers
            
            if ($status -eq 0) {
                Write-Host "All Shecan DNS servers are working perfectly!" -ForegroundColor Green
            } elseif ($status -eq 1) {
                Write-Host "Primary DNS unavailable, but secondary is working" -ForegroundColor Yellow
            } else {
                Write-Host "Both Shecan DNS servers unavailable, using Google DNS" -ForegroundColor Yellow
                Write-Host "Run 'shecan start' to apply the working DNS configuration" -ForegroundColor Yellow
            }
        }
        default {
            Write-Host "Shecan DNS Manager - Windows"
            Write-Host "Usage: shecan {start|stop|status|test}"
        }
    }
}
'@

Set-Content -Path "$installPath\shecan.ps1" -Value $command

$config = @{
    Mode = $mode
    Dns1 = $dns1
    Dns2 = $dns2
    DdnsPassword = $ddnsPassword
}
$config | ConvertTo-Json | Out-File "$installPath\config.json" -Encoding utf8

$profilePath = "$env:USERPROFILE\Documents\PowerShell\Microsoft.PowerShell_profile.ps1"
$profileDir = Split-Path $profilePath

if (-not (Test-Path $profileDir)) {
    New-Item -ItemType Directory -Path $profileDir -Force | Out-Null
}

$profileEntry = ". `"$installPath\shecan.ps1`""
if (-not (Test-Path $profilePath) -or -not (Select-String -Path $profilePath -Pattern $profileEntry -Quiet)) {
    Add-Content -Path $profilePath -Value $profileEntry
}

Write-Host ""
Write-Host "Installation Complete!"
Write-Host ""
Write-Host "The 'shecan' command is now available in PowerShell."
Write-Host ""
Write-Host "Usage:"
Write-Host "  shecan start   - Enable Shecan DNS"
Write-Host "  shecan stop    - Disable Shecan DNS"
Write-Host "  shecan status  - Show current status"
Write-Host "  shecan test    - Test DNS servers"
Write-Host ""
Write-Host "Note: Restart PowerShell or run this to use immediately:"
Write-Host "  $profileEntry"
Write-Host ""