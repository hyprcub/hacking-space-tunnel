#!/bin/sh

#############
# Preambule #
#############

# Script Metadata
SCRIPT_NAME="HackSpaceTunnel"
SCRIPT_VERSION="1.0.0"
SCRIPT_DATE="2024-01-07"  # Date of the script's last update
AUTHOR_NAME="Laurent Hofer <hyprcub@hyprcub.rocks>"
COPYRIGHT_YEAR="2024"

# License
LICENSE="This program is free software: you can redistribute it and/or modify \
it under the terms of the GNU General Public License as published by \
the Free Software Foundation, either version 3 of the License, or \
(at your option) any later version.

This program is distributed in the hope that it will be useful, \
but WITHOUT ANY WARRANTY; without even the implied warranty of \
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the \
GNU General Public License for more details.

You should have received a copy of the GNU General Public License \
along with this program. If not, see <https://www.gnu.org/licenses/>."


############
# Settings #
############
_DEBUG=1

# Change these if you really want to
WORKDIR="$HOME/.cache/hstnl"
CONFDIR="$HOME/.config/hstnl" # Put your .ovpn files there

for d in $WORKDIR $CONFDIR; do
    mkdir -p $d
done


#################################
# Messages with pretty coloring #
#################################
_msg() {
    if [ "$#" -lt 2 ]; then
        echo
        echo "Usage: _msg <type> <message>"
        echo
        echo "Type must be one of the following:"
        _msg notice "\e[1mnotice\e[0m"
        _msg warning "\e[1mwarning\e[0m"
        _msg error "\e[1merror\e[0m"
        _msg success "\e[1msuccess\e[0m"
        _DEBUG=1 ; _msg debug "\e[1mdebug\e[0m which displays iff _DEBUG=1"
        return 1
    fi

    local type="$1"
    shift ; local message="$*"
    local pchars

    if [ "$type" = "debug" ] && [ "$_DEBUG" -ne 1 ]; then
        return 0
    fi

    case $type in
        notice) pchars="\e[1m[-]\e[0m" ;;
        warning) pchars="\e[1;93m[!]\e[0m" ;;
        error) pchars="\e[1;91m[!]\e[0m" ;;
        success) pchars="\e[1;92m[+]\e[0m" ;;
        debug) pchars="\e[1;94m[*]\e[0m" ;;
        *) pchars="\e[1m[?]\e[0m"; echo "Unknown message type: $type"; return 1 ;;
    esac

    printf "%b %b\n" "$pchars" "$message"
}


#####################################
# Executes command and catch errors #
#####################################
_cmd() {
    "$@" >/dev/null 2>&1
    local status_code=$?

    if [ $status_code -ne 0 ]; then
        _msg error "Something went wrong when executing: \e[1m$@\e[0m"
        return $status_code
    fi
}


#######################################
# Installing up.sh, needed by OpenVPN #
#######################################

# Location of up.sh
current_shell=$(ps -p $$ -o comm=)

if [ "$current_shell" = "zsh" ]; then
    setopt nullglob
    scriptdir=$(dirname "$(realpath "$0")")
else
    # We assume we're running bash.
    # Thank you Dave Dopson!
    # https://stackoverflow.com/questions/59895/how-do-i-get-the-directory-where-a-bash-script-is-located-from-within-the-script
    scriptdir=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
fi

if [ -n "$scriptdir" ]; then
    UPSH="$scriptdir/up.sh"
else
    _msg error "Something went wrong when defining \e[1m\$scriptdir\e[0m"
    return 1
fi

# up.sh content
_write_upsh() {
    cat > "$1" 2> /dev/null << 'EOT'
#!/bin/sh
WORKDIR=$1

echo "$ifconfig_local" > "$WORKDIR/lhost"
echo "$route_vpn_gateway" > "$WORKDIR/vpn_gw_ip"
EOT
    if [ $? -ne 0 ]; then return 1; fi

    chmod 0700 "$1" > /dev/null 2>&1
    if [ $? -ne 0 ]; then return 1; fi
}

# 
_install_upsh() {
    if [ -f "$UPSH" ]; then # If up.sh already exist, compare it and make a backup if needed

        local TMPDIR=$(mktemp -d) # Temporary directory to write a good version of up.sh to compare with
        trap 'rm -rf "$TMPDIR"; return 1' INT TERM ERR # Ensure that the temporary directory is deleted

        _write_upsh "$TMPDIR/up.sh"
        _msg debug "\e[1m'$TMPDIR/up.sh'\e[0m created"

        if cmp -s "$UPSH" "$TMPDIR/up.sh"; then # The comparison itself
            _msg debug "\e[1m'$UPSH'\e[0m is fine. Nothing to do."
            return 0
        else
            _msg notice "\e[1m'up.sh'\e[0m already exist and is different, trying to make a backup."
            _cmd mv "$UPSH" "${UPSH}.bak"
            _msg success "Backup successfully created."
        fi

        _cmd rm -rf "$TMPDIR"
        trap - INT TERM ERR # Restore default trap behavior
    fi

    if _write_upsh "$UPSH"; then
        _msg success "\e[1m'up.sh'\e[0m created."
    else
        _msg error "Something went wrong when creating \e[1m'up.sh'\e[0m"
    fi
}


###############
# Tools needed#
###############
_check_tools() {
    local tools_needed=(sudo openvpn)
    local tools_found=true

    _msg debug "Checking for the tools needed:"
    for tools in "${tools_needed[@]}"; do
        if command -v "$tools" > /dev/null 2>&1; then
            _msg debug "\t\e[1m$tools\e[0m found"
        else
            _msg error "\t\e[1m$tools\e[0m not found"
            tools_found=false
        fi
    done

    if [ "$tools_found" = false ]; then
        _msg notice "Please install the required tools."
        return 1
    fi
}


############
# Routines #
############
_show_help() {
    echo
    echo "$SCRIPT_NAME v$SCRIPT_VERSION"
    echo
    echo "Usage: $0 <config_name | 'status' | 'stop'>"
    echo
    echo "Arguments:"
    echo "  config_name    Name of the configuration file (without the .ovpn extension)."
    echo "                 The \e[1m'config_name.ovpn'\e[0m file must be located in the directory:"
    echo "                 $CONFDIR"
    echo
    echo "  'status'       Check the status of the VPN connection."
    echo "  'stop'         Stop the VPN connection."
}


_set_env() {
    local var_to_set=(lhost lab pid vpn_gw_ip)

    for f in "${var_to_set[@]}"; do
        local file_path="$WORKDIR/$f"
        if [ ! -f "$file_path" ]; then
            _msg error "\e[1m'$f'\e[0m is missing in $WORKDIR, something is wrong"
            return 1
        else
            local content=$(cat "$file_path")
            if [ -z "$content" ]; then
                _msg error "The file \e[1m'$f'\e[0m is empty, something is wrong"
                return 1
            fi
            export "$f=$content"
            _msg notice "\t$f=$content"
        fi
    done

    _msg success "Environment variables set correctly."
}


_unset_env() {
    local var_to_unset=(lhost lab pid vpn_gw_ip)
    unset $var_to_unset
}


_clean_up() {
    local files_to_clean=(pid lhost lab vpn_gw_ip)

    for f in "${files_to_clean[@]}"; do
        local file_path="$WORKDIR/$f"
        local file_found=false

        if [ -f "$file_path" ]; then
            rm -f "$file_path"
            #_msg success "Removed $f file."
            file_found=true
        fi
    done

    if [ "$file_found" = false ]; then
        _msg notice "No files to clean up."
    else
        _msg notice "Files cleaned up"
    fi
}


_check_ovpn_config_file() {
    return 0
    # TODO: find a way to check OpenVNP syntax
}


_check_vpn_status() {
    local pid_file="$WORKDIR/pid"
    local vpn_gw_ip_file="$WORKDIR/vpn_gw_ip"
    local lab_file="$WORKDIR/lab"
    local lhost_file="$WORKDIR/lhost"
    local vpn_active=false

    if [ -f "$pid_file" ]; then
        local vpn_pid=$(cat "$pid_file")

        if [ -n "$vpn_pid" ]; then
            if ps -p "$vpn_pid" > /dev/null 2>&1; then
                _msg notice "OpenVPN process with PID $vpn_pid is running."
                vpn_active=true
            else
                _msg error "OpenVPN process with PID $vpn_pid is not running."
            fi
        else
            _msg error "VPN PID file is empty, something is wrong"
        fi
    else
        _msg warning "VPN PID file does not exist so there is probably no VPN connection."

        local pid=$(pgrep openvpn 2> /dev/null | tr '\n' ' ')
        if [ ! -z $pid ]; then
            _msg warning "But there may be some OpenVPN process running with PID: $pid."
        fi
        return 1
    fi

    if [ "$vpn_active" = true ]; then
        if [ -f "$vpn_gw_ip_file" ]; then
            local vpn_gw_ip=$(cat "$vpn_gw_ip_file")

            if [ -n "$vpn_gw_ip" ] && ping -c 1 "$vpn_gw_ip" > /dev/null 2>&1; then
                _msg success "VPN connection is functional and traffic is routed correctly."
            else
                _msg warning "VPN connection is established but traffic is not routed correctly or remote VPN IP is missing."
                return 1
            fi
        else
            _msg warning "Remote VPN IP file does not exist."
            return 1
        fi
    fi
}


_vpn_connect() {
    local lab=$(basename "$1" | cut -d'.' -f1)

    _msg notice "Connecting to $lab"
    sudo openvpn --config "$1" --writepid "$WORKDIR/pid" --up "$scriptdir/up.sh $WORKDIR" --script-security 2 --daemon > /dev/null 2>&1
    while [ ! -f "$WORKDIR/lhost" ]; do
        sleep 0.5s
        echo -n "."
    done
    echo
    echo $lab > "$WORKDIR/lab"
    _msg success "VPN connection established."
}


_vpn_disconnect() {
    local vpn_pid=$(cat "$WORKDIR/pid")

    sudo kill "$vpn_pid" && _msg success "Stopped VPN process with PID $vpn_pid."
}

########
# Main #
########

hstnl() {
    _msg debug "Running shell: \e[1m$current_shell\e[0m"
    _msg debug "Working dir: \e[1m$WORKDIR\e[0m"
    _msg debug "Config dir:\e[1m$CONFDIR\e[0m"
    _msg debug "Script dir: \e[1m$scriptdir\e[0m"
    _msg debug "up.sh path: \e[1m$UPSH\e[0m"

    _check_tools
    _install_upsh

    if [ "$#" -eq 0 ]; then
        _msg warning "No argument provided."
        _show_help
        return 1
    else
        _msg debug "Argument(s) provided: \e[1m$*\e[0m"
    fi

    local config_files=($(ls "$CONFDIR"/*.ovpn 2>/dev/null))

    if [ -z "$config_files" ]; then
        _msg warning "No .ovpn config files found in $CONFDIR"
        _show_help
        return 1
    else
        _msg debug "List of config files:"
        for f in "${config_files[@]}"; do
            _msg debug "\t\e[1m$(basename $f)\e[0m"
        done
    fi

    vpn_config="$CONFDIR/$1.ovpn"

    if [ -f "$vpn_config" ]; then
        if ! _check_ovpn_config_file "$vpn_config"; then
            _msg error "\e[1m'$vpn_config'\e[0m is not a valid OpenVPN configuration file."
            return 1
        fi
        if ! _check_vpn_status > /dev/null 2>&1; then
            _vpn_connect "$vpn_config"
        else
            _msg success "Already connected to a VPN: \e[1m$lab\e[0m"
        fi
        _set_env
    else
        case $1 in
            "status")
                if _check_vpn_status; then
                    _set_env
                fi
                ;;
            "stop")
                if _check_vpn_status; then
                    _vpn_disconnect
                    _clean_up
                    _unset_env
                fi
                ;;
            *)
                _msg warning "\e[1m'$1.ovpn'\e[0m does not exist."
                _show_help
                return 1
                ;;
        esac
    fi

    unset WORKDIR CONFDIR
}
