# HackSpaceTunnel
A (collection of) very simple script(s) for managing VPN connections to virtual hacking labs

## Installation

Put the file `hackspace-tunnel.sh` wherever you like in a writable directory, let's say in `~/.local/bin`:
```shell
mkdir -p ~/.local/bin
wget https://raw.githubusercontent.com/hyprcub/hackspace-tunnel/main/hackspace-tunnel.sh -O ~/.local/bin/hstnl
```

Add this line to your `.bashrc` or `.zshrc` (if needed):
```shell
export PATH=${PATH}:${HOME}/.local/bin
```

## Usage

Download your `.ovpn` configuration files from your favorite hacking labs (HackTheBox, TryHackMe or whatever) and put them in `~/.config/hstnl`. The rest is self explanatory:
```
HackSpaceTunnel v1.0.0

Usage: ./hackspace-tunnel.sh <config_name | 'status' | 'stop' | 'list'> [-q|--quiet]

Arguments:
  config         Name of the configuration file (without the .ovpn extension).
                 The 'config.ovpn' file must be located in the directory:
                 /home/laurenth/.config/hstnl

  'status'       Check the status of the VPN connection.
  'list'         List available OpenVPN configuration files.
  'stop'         Stop the VPN connection.

Options:
  -q, --quiet    Enable quiet mode. Minimizes the output of the script.
```

