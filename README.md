# Shecan DNS Script

Cross-platform DNS management script for https://shecan.ir with automatic failover and DDNS support.

## Features

- One command installation for Linux, macOS, and Windows
- DDNS auto-updates for Premium users (Every 5 minutes)
- Automatic DNS failover (Google DNS fallback)
- Free and Premium plan support

## Installation

### Linux

```bash
sudo bash -c "$(curl -fsSL \
  https://raw.githubusercontent.com/r3nzodev/shecan-script/main/shecanlinux.sh)"
```


### macOS

```bash
sudo bash -c "$(curl -fsSL \
  https://raw.githubusercontent.com/r3nzodev/shecan-script/main/shecanmac.sh)"
```


### Windows

Run PowerShell as Administrator:

```powershell
irm https://raw.githubusercontent.com/r3nzodev/shecan-script/main/shecanwin.ps1 | iex
```

## Usage


```bash
# Linux/macOS
sudo shecan start    # Enable Shecan DNS
sudo shecan stop     # Disable Shecan DNS
sudo shecan status   # Show current status
sudo shecan test     # Test DNS connectivity

# Windows (in PowerShell as Admin)
shecan start
shecan stop
shecan status
shecan test
```

## Plans

- **FREE:** Limited Speed (178.22.122.100, 185.51.200.2)
- **PREMIUM:** (178.22.122.101, 185.51.200.1) + DDNS auto-updates

## License

MIT
