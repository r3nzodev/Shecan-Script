#!/bin/bash

# Shecan DNS Manager - macOS Universal Setup
set -e

echo "Shecan DNS Manager - macOS Setup"
echo "===================================="

if [ "$EUID" -ne 0 ]; then
    echo "Please run as root or with sudo"
    exit 1
fi

if [ "$(uname)" != "Darwin" ]; then
    echo "Error: This installer is for macOS only"
    exit 1
fi

# Check dependencies
for cmd in networksetup dscacheutil killall curl; do
    if ! command -v $cmd &>/dev/null; then
        echo "Missing required command: $cmd"
        exit 1
    fi
done

echo ""
echo "Select Your Shecan Plan:"
echo "1) FREE User (178.22.122.100, 185.51.200.2)"
echo "2) PREMIUM User (178.22.122.101, 185.51.200.1 + DDNS)"
read -p "Enter choice (1 or 2): " user_choice

case $user_choice in
    1)
        mode="free"
        primary_dns="178.22.122.100"
        secondary_dns="185.51.200.2"
        ;;
    2)
        mode="premium"
        primary_dns="178.22.122.101"
        secondary_dns="185.51.200.1"
        
        echo ""
        echo "Enter your Shecan DDNS Password Token:"
        echo "Only the token part (not the full URL)"
        echo ""
        echo "Example:"
        echo "If your URL is: https://ddns.shecan.ir/update?password=bfdf57e92c9d6"
        echo "Then enter only: bfdf57e92c9d6"
        echo ""
        read -p "Password Token: " ddns_password
        
        ddns_password=$(echo "$ddns_password" | sed 's|.*password=||' | sed 's|[^a-zA-Z0-9].*||')
        
        if [ -z "$ddns_password" ]; then
            echo "Password token required for premium users"
            exit 1
        fi
        ;;
    *)
        echo "Invalid choice" && exit 1
        ;;
esac

echo ""
echo "Installing shecan command..."
cat > /usr/local/bin/shecan << 'EOF'
#!/bin/bash

[ "$EUID" -ne 0 ] && echo "Please run with sudo" && exit 1
[ ! -f /etc/shecan/config ] && echo "Run installer first" && exit 1
source /etc/shecan/config

get_service() { networksetup -listallnetworkservices | grep -v "^*" | grep -v "Bluetooth" | head -1; }

flush_dns() {
    echo "Flushing DNS cache..."
    dscacheutil -flushcache
    killall -HUP mDNSResponder 2>/dev/null || true
    echo "DNS cache flushed"
}

test_dns() {
    nslookup google.com $primary_dns &>/dev/null && { CURRENT_DNS1=$primary_dns; CURRENT_DNS2=$secondary_dns; return 0; }
    nslookup google.com $secondary_dns &>/dev/null && { CURRENT_DNS1=$secondary_dns; CURRENT_DNS2="8.8.8.8"; return 1; }
    CURRENT_DNS1="8.8.8.8"; CURRENT_DNS2="8.8.4.4"; return 2
}

case "$1" in
    start)
        service=$(get_service); [ -z "$service" ] && echo "No active network service" && exit 1
        
        flush_dns
        
        test_dns; status=$?
        echo "Applying DNS to: $service"
        echo "Using: $CURRENT_DNS1, $CURRENT_DNS2"
        networksetup -setdnsservers "$service" $CURRENT_DNS1 $CURRENT_DNS2
        [ "$mode" = "premium" ] && launchctl load -w /Library/LaunchDaemons/com.shecan.ipupdate.plist 2>/dev/null || true
        
        flush_dns
        
        echo "Shecan DNS activated (Mode: $mode)"
        [ $status -eq 1 ] && echo "Note: Using secondary DNS"
        [ $status -eq 2 ] && echo "Note: Using Google DNS fallback"
        ;;
    stop)
        service=$(get_service); [ -z "$service" ] && echo "No active network service" && exit 1
        [ "$mode" = "premium" ] && launchctl unload -w /Library/LaunchDaemons/com.shecan.ipupdate.plist 2>/dev/null || true
        networksetup -setdnsservers "$service" "Empty"
        flush_dns
        echo "Shecan DNS deactivated"
        ;;
    status)
        echo "Shecan Status: Mode: $mode, DNS: $primary_dns, $secondary_dns"
        service=$(get_service); [ -n "$service" ] && echo "Service: $service" && networksetup -getdnsservers "$service"
        [ "$mode" = "premium" ] && { launchctl list | grep -q com.shecan.ipupdate && echo "DDNS: ACTIVE" || echo "DDNS: INACTIVE"; }
        ;;
    test)
        flush_dns
        
        test_dns; status=$?
        [ $status -eq 0 ] && echo "All Shecan DNS servers working"
        [ $status -eq 1 ] && echo "Primary DNS failed, secondary working"
        [ $status -eq 2 ] && echo "Both Shecan DNS failed, using Google DNS"
        ;;
    *) echo "Usage: sudo shecan {start|stop|status|test}" ;;
esac
EOF

chmod +x /usr/local/bin/shecan

mkdir -p /etc/shecan
cat > /etc/shecan/config << EOF
mode="$mode"
primary_dns="$primary_dns"
secondary_dns="$secondary_dns"
ddns_password="$ddns_password"
EOF

if [ "$mode" = "premium" ]; then
    echo "Setting up DDNS service..."
    
    cat > /Library/LaunchDaemons/com.shecan.ipupdate.plist << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>com.shecan.ipupdate</string>
    <key>ProgramArguments</key><array><string>/usr/bin/curl</string><string>-s</string><string>https://ddns.shecan.ir/update?password=${ddns_password}</string></array>
    <key>StartInterval</key><integer>300</integer><key>RunAtLoad</key><true/>
</dict>
</plist>
EOF
    
    chmod 644 /Library/LaunchDaemons/com.shecan.ipupdate.plist
fi

echo ""
echo "Installation Complete!"
echo ""
echo "Usage: sudo shecan {start|stop|status|test}"
echo "Try: sudo shecan test"
echo ""