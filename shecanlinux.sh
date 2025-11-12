#!/bin/bash

set -e

echo "Shecan DNS Manager - Linux Setup"
echo "===================================="

if [ "$EUID" -ne 0 ]; then
    echo "Please run as root or with sudo"
    exit 1
fi

if [ -f /etc/os-release ]; then
    . /etc/os-release
    DISTRO="$ID"
else
    echo "Cannot detect distribution"
    exit 1
fi

for cmd in curl nmcli systemctl nslookup; do
    if ! command -v $cmd &>/dev/null; then
        echo "Missing: $cmd"
        case "$cmd" in
            nmcli)
                echo "Install NetworkManager:"
                case "$DISTRO" in
                    arch) echo "  pacman -S networkmanager" ;;
                    fedora|centos|rhel) echo "  dnf install NetworkManager" ;;
                    debian|ubuntu|*) echo "  apt install network-manager" ;;
                esac
                ;;
            nslookup)
                echo "Install dnsutils:"
                case "$DISTRO" in
                    arch) echo "  pacman -S bind" ;;
                    fedora|centos|rhel) echo "  dnf install bind-utils" ;;
                    debian|ubuntu|*) echo "  apt install dnsutils" ;;
                esac
                ;;
        esac
        exit 1
    fi
done

if ! systemctl is-active --quiet NetworkManager; then
    echo "Error: NetworkManager not active. Start it with:"
    echo "  systemctl start NetworkManager"
    echo "  systemctl enable NetworkManager"
    exit 1
fi

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
        echo "If your URL is: https://ddns.shecan.ir/update?password=bfdf57e82c9d6"
        echo "Then enter only: bfdf57e82c9d6"
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

get_conn() { nmcli -t -f NAME connection show --active | head -1; }

flush_dns() {
    echo "Flushing DNS cache..."
    command -v resolvectl &>/dev/null && resolvectl flush-caches 2>/dev/null || true
    command -v systemd-resolve &>/dev/null && systemd-resolve --flush-caches 2>/dev/null || true
    systemctl is-active nscd &>/dev/null && systemctl restart nscd 2>/dev/null || true
    systemctl is-active dnsmasq &>/dev/null && systemctl restart dnsmasq 2>/dev/null || true
    ip route flush cache 2>/dev/null || true
    echo "DNS cache flushed"
}

test_dns() {
    nslookup google.com $primary_dns &>/dev/null && { CURRENT_DNS1=$primary_dns; CURRENT_DNS2=$secondary_dns; return 0; }
    nslookup google.com $secondary_dns &>/dev/null && { CURRENT_DNS1=$secondary_dns; CURRENT_DNS2="8.8.8.8"; return 1; }
    CURRENT_DNS1="8.8.8.8"; CURRENT_DNS2="8.8.4.4"; return 2
}

case "$1" in
    start)
        conn=$(get_conn); [ -z "$conn" ] && echo "No active connection" && exit 1
        
        flush_dns
        
        test_dns; status=$?
        echo "Applying DNS to: $conn"
        echo "Using: $CURRENT_DNS1, $CURRENT_DNS2"
        nmcli con mod "$conn" ipv4.dns "$CURRENT_DNS1 $CURRENT_DNS2"
        nmcli con mod "$conn" ipv4.ignore-auto-dns yes
        nmcli con up "$conn"
        [ "$mode" = "premium" ] && systemctl enable --now shecan-ipupdate.timer 2>/dev/null || true
        
        flush_dns
        
        echo "Shecan DNS activated (Mode: $mode)"
        [ $status -eq 1 ] && echo "Note: Using secondary DNS"
        [ $status -eq 2 ] && echo "Note: Using Google DNS fallback"
        ;;
    stop)
        conn=$(get_conn); [ -z "$conn" ] && echo "No active connection" && exit 1
        [ "$mode" = "premium" ] && systemctl disable --now shecan-ipupdate.timer 2>/dev/null || true
        nmcli con mod "$conn" ipv4.dns ""
        nmcli con mod "$conn" ipv4.ignore-auto-dns no
        nmcli con up "$conn"
        flush_dns
        echo "Shecan DNS deactivated"
        ;;
    status)
        echo "Shecan Status: Mode: $mode, DNS: $primary_dns, $secondary_dns"
        conn=$(get_conn); [ -n "$conn" ] && echo "Connection: $conn" && nmcli -f ipv4.dns con show "$conn"
        [ "$mode" = "premium" ] && { systemctl is-active shecan-ipupdate.timer &>/dev/null && echo "DDNS: ACTIVE" || echo "DDNS: INACTIVE"; }
        ;;
    test)
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
    
    cat > /etc/systemd/system/shecan-ipupdate.service << EOF
[Unit]
Description=Shecan IP Update
After=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/bin/curl -s "https://ddns.shecan.ir/update?password=${ddns_password}"
EOF

    cat > /etc/systemd/system/shecan-ipupdate.timer << EOF
[Unit]
Description=Shecan DDNS Timer

[Timer]
OnBootSec=1min
OnUnitActiveSec=5min
Unit=shecan-ipupdate.service

[Install]
WantedBy=timers.target
EOF

    systemctl daemon-reload
fi

echo ""
echo "Installation Complete!"
echo ""
echo "Usage: sudo shecan {start|stop|status|test}"
echo "Try: sudo shecan test"
echo ""