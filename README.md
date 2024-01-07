# HackSpaceTunnel
A (collection of) very simple script(s) for managing VPN connections to virtual hacking labs

## Installation

Put the file `hackspace-tunnel.sh` wherever you like in a writable directory, let's say in `~/.local/share/hstnl`:
```shell
mkdir -p ~/.local/share/hstnl
wget https://github.com/hyprcub/hackspace-tunnel/master/hackspace-tunnel.sh -O ~/.local/share/hstnl/hackspace-tunnel.sh
```

Add these lines to your `.bashrc` or `.zshrc`:
```shell
# HackSpaceTunnel
hstnl=$HOME/.local/share/hackspace-tunnel.sh
if [[ -e "$hstnl" ]]; then
	source "$hstnl"
fi
```

## Usage

Download your `.ovpn` configuration files from your favorite hacking labs (HackTheBox, TryHackMe or whatever) and put them in `~/.config/hstnl`. The rest is self explanatory:
```
Usage: _show_help <config_name | 'status' | 'stop'>

Arguments:
  config_name    Name of the configuration file (without the .ovpn extension).
                 The 'config_name.ovpn' file must be located in the directory:
                 /home/laurenth/.config/hstnl

  'status'       Check the status of the VPN connection.
  'stop'         Stop the VPN connection.
```

