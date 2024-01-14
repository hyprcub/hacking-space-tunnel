#!/usr/bin/env bash

#############
# Preambule #
#############

# Script Metadata
SCRIPT_NAME="HackSpaceTunnel"
SCRIPT_VERSION="1.0.0"
SCRIPT_DATE="2024-01-14" # Date of the script's last update
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
: ${DEBUG:=0}
: ${QUIET_MODE:=0}
: ${ANSI:=1}

# Don't change these
HSTNL_CONF_DIR="$HOME/.config/hstnl" # Put your .ovpn files there
HSTNL_WORK_DIR="$HOME/.cache/hstnl"
ENV_FILE="$HSTNL_WORK_DIR/env.sh"

for d in $HSTNL_WORK_DIR $HSTNL_CONF_DIR; do
	mkdir -p $d
done

#################################
# Messages with pretty coloring #
#################################
initialize_ansi() {
	bold="\e[1m"
	reset="\e[0m"
	green="\e[1;92m"
	blue="\e[1;94m"
	red="\e[1;91m"
	yellow="\e[1;93m"
}

_echo() {
	printf "%b\n" "$@"
}

msg() {
	# Check arguments
	if [ "$#" -lt 2 ]; then
		_echo
		_echo "Usage: msg <type> <message>"
		_echo
		_echo "Type must be one of the following:"
		msg notice "${bold}notice${reset}"
		msg warning "${bold}warning${reset}"
		msg error "${bold}error${reset}"
		msg success "${bold}success${reset}"

		local previous_state=$DEBUG
		DEBUG=1
		msg debug "${bold}debug${reset} which displays iff DEBUG=1"
		DEBUG=$previous_state

		return 1
	fi

	local type="$1"
	shift
	local message="$*"
	local pchars

	# Don't display anything if DEBUG is not set to 1
	[[ $type == debug && $DEBUG != 1 ]] && return 0

	case $type in
	notice) pchars="${bold}[-]${reset}" ;;
	warning) pchars="${yellow}[!]${reset}" ;;
	error) pchars="${red}[x]${reset}" ;;
	success) pchars="${green}[+]${reset}" ;;
	debug) pchars="${blue}[*]${reset}" ;;
	*)
		pchars="${bold}[?]${reset}"
		printf "%b\n" "Unknown message type: $type"
		return 1
		;;
	esac

	# Don't display anything if in quiet mode
	[[ $QUIET_MODE != 1 ]] && printf "%b %b\n" "$pchars" "$message"
}

#####################################
# Executes command and catch errors #
#####################################
cmd() {
	"$@" >/dev/null 2>&1
	local status_code=$?

	if [ $status_code -ne 0 ]; then
		msg error "Something went wrong when executing: ${bold}$@${reset}"
		exit $status_code
	fi
}

#######################################
# Installing up.sh, needed by OpenVPN #
#######################################
# Define path to up.sh
declare -r SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd) # Making it read-only to prevent playing with it

if [ -n "$SCRIPT_DIR" ]; then
	UPSH="$SCRIPT_DIR/up.sh"
else
	msg error "Something went wrong when defining ${bold}\$SCRIPT_DIR${reset}"
	exit 1
fi

# Write up.sh content
_write_upsh() {
	cat >"$1" 2>/dev/null <<'EOF'
#!/bin/sh
HSTNL_WORK_DIR=$1

echo "$ifconfig_local" > "$HSTNL_WORK_DIR/lhost"
echo "$route_vpn_gateway" > "$HSTNL_WORK_DIR/vpn_gw_ip"
EOF
	if [ $? -ne 0 ]; then return 1; fi

	chmod 0700 "$1" >/dev/null 2>&1
	if [ $? -ne 0 ]; then return 1; fi
}

#
_install_upsh() {
	if [ -f "$UPSH" ]; then # If up.sh already exist, compare it and make a backup if needed

		local TMPDIR=$(mktemp -d) # Temporary directory to write a good version of up.sh to compare with
		trap 'rm -rf "$TMPDIR"; return 1' INT TERM ERR

		_write_upsh "$TMPDIR/up.sh"
		msg debug "${bold}'$TMPDIR/up.sh'${reset} created"

		if cmp -s "$UPSH" "$TMPDIR/up.sh"; then # The comparison itself
			msg debug "${bold}'$UPSH'${reset} is fine. Nothing to do."
			return 0
		fi

		msg notice "${bold}'up.sh'${reset} already exist and is different, trying to make a backup."

		if ! cmd mv "$UPSH" "${UPSH}.bak"; then
			msg error "Can't make a backup of $UPSH, aborting."
			exit 1
		fi

		msg success "Backup successfully created."

		cmd rm -rf "$TMPDIR"
		trap - INT TERM ERR
	fi

	if _write_upsh "$UPSH"; then
		msg success "${bold}'up.sh'${reset} created."
	else
		msg error "Something went wrong when creating ${bold}'up.sh'${reset}"
		exit 1
	fi
}

###############
# Tools needed#
###############
_ensure_dependencies() {
	local tools_needed=(sudo openvpn)
	local tools_found=true

	msg debug "Checking for the tools needed:"

	for tools in "${tools_needed[@]}"; do
		if command -v "$tools" >/dev/null 2>&1; then
			msg debug "\t${bold}$tools${reset} found"
		else
			msg notice "\t${bold}$tools${reset} not found"
			tools_found=false
		fi
	done

	if [ "$tools_found" = false ]; then
		msg error "Please install the required tools."
		exit 1
	fi
}

#############
# Functions #
#############
_set_env() {
	local var_to_set=(lhost lab pid vpn_gw_ip)

	msg notice "Setting environment variables:"

	>$ENV_FILE # Initialize ENV_FILE

	for f in "${var_to_set[@]}"; do
		local file_path="$HSTNL_WORK_DIR/$f"
		if [ ! -f "$file_path" ]; then
			msg error "${bold}'$f'${reset} is missing in $HSTNL_WORK_DIR, something is wrong"
			return 1
		else
			local content=$(cat "$file_path")
			if [ -z "$content" ]; then
				msg error "The file ${bold}'$f'${reset} is empty, something is wrong"
				return 1
			fi
			cat >>$ENV_FILE <<EOF
export $f="$content"
EOF
			msg notice "\t$f=$content"
		fi
	done
	# write to rc file
	msg success "Environment variables set correctly."
}

_unset_env() {
	local var_to_unset=(lhost lab pid vpn_gw_ip)
	unset $var_to_unset
}

###################
# Inner functions #
###################
_show_help() {
	_echo
	_echo "$SCRIPT_NAME v$SCRIPT_VERSION"
	_echo
	_echo "Usage: $0 <config_name | 'status' | 'stop' | 'list'> [-q|--quiet]"
	_echo
	_echo "Arguments:"
	_echo "  config         Name of the configuration file (without the .ovpn extension)."
	_echo "                 The ${bold}'config.ovpn'${reset} file must be located in the directory:"
	_echo "                 $HSTNL_CONF_DIR"
	_echo
	_echo "  'status'       Check the status of the VPN connection."
	_echo "  'list'         List available OpenVPN configuration files."
	_echo "  'stop'         Stop the VPN connection."
	_echo
	_echo "Options:"
	_echo "  -q, --quiet    Enable quiet mode. Minimizes the output of the script."
	_echo
}

_clean_up() {
	local files_to_clean=(pid lhost lab vpn_gw_ip env.sh)
	local file_found=false
	local file_path

	for f in "${files_to_clean[@]}"; do
		file_path="$HSTNL_WORK_DIR/$f"

		if [ -f "$file_path" ]; then
			cmd rm -f "$file_path"
			file_found=true
		fi
	done

	if [[ $file_found == false ]]; then
		msg notice "Some files were missing."
	else
		msg notice "Files cleaned up."
	fi
}

_list_config_files() {
	local config_files=($(ls "$HSTNL_CONF_DIR"/*.ovpn 2>/dev/null))

	if [ -z "$config_files" ]; then
		msg warning "No .ovpn config files found in $HSTNL_CONF_DIR"
		_show_help
		return 1
	else
		msg notice "Available OpenVPN config files:"
		for f in "${config_files[@]}"; do
			msg notice "\t${bold}$(basename $f)${reset}"
		done
	fi
}

_vpn_status() {
	local pid_file="$HSTNL_WORK_DIR/pid"
	local vpn_gw_ip_file="$HSTNL_WORK_DIR/vpn_gw_ip"
	local lab_file="$HSTNL_WORK_DIR/lab"
	local lhost_file="$HSTNL_WORK_DIR/lhost"
	local vpn_active=false

	if [ -f "$pid_file" ]; then
		local vpn_pid=$(cat "$pid_file")

		if [ -n "$vpn_pid" ]; then
			if ps -p "$vpn_pid" >/dev/null 2>&1; then
				msg notice "OpenVPN process with PID $vpn_pid is running."
				vpn_active=true
			else
				msg error "OpenVPN process with PID $vpn_pid is not running."
			fi
		else
			msg error "VPN PID file is empty, something is wrong"
		fi
	else
		msg warning "VPN PID file does not exist so there is probably no VPN connection."

		local pid=$(pgrep openvpn 2>/dev/null | tr '\n' ' ')
		if [ ! -z $pid ]; then
			msg warning "But there may be some OpenVPN process running with PID: $pid."
		fi
		return 1
	fi

	if [ "$vpn_active" = true ]; then
		if [ -f "$vpn_gw_ip_file" ]; then
			local vpn_gw_ip=$(cat "$vpn_gw_ip_file")

			if [ -n "$vpn_gw_ip" ] && ping -c 1 "$vpn_gw_ip" >/dev/null 2>&1; then
				msg success "VPN connection is functional and traffic is routed correctly."
			else
				msg warning "VPN connection is established but traffic is not routed correctly or remote VPN IP is missing."
				return 1
			fi
		else
			msg warning "Remote VPN IP file does not exist."
			return 1
		fi
	fi
}

_vpn_connect() {
	local lab=$(basename "$1" | cut -d'.' -f1)
	local timeout=10 # Timeout delay in seconds

	msg notice "Connecting to ${bold}'$lab'${reset}"
	sudo openvpn --config "$1" --writepid "$HSTNL_WORK_DIR/pid" --up "$SCRIPT_DIR/up.sh $HSTNL_WORK_DIR" --script-security 2 --daemon >/dev/null 2>&1

	local start_time=$(date +%s)

	while [ ! -f "$HSTNL_WORK_DIR/lhost" ]; do # Waiting for connection or timeout
		sleep 0.5s
		local current_time=$(date +%s)
		local elapsed=$(($current_time - $start_time))

		if [ $elapsed -ge $timeout ]; then
			msg error "Timeout reached while waiting for VPN connection."
			msg warning "You should check manually what happend."
			exit 1
		fi

		printf "%b" "."
	done

	echo
	echo $lab >"$HSTNL_WORK_DIR/lab"
	msg success "VPN connection established."
}

_vpn_disconnect() {
	local vpn_pid=$(cat "$HSTNL_WORK_DIR/pid")

	sudo kill "$vpn_pid" && msg success "Stopped VPN process with PID $vpn_pid." # TODO: Improve here
}

########
# Main #
########
hstnl() {
	while getopts ":q" opt; do
		case "$opt" in
		q) QUIET_MODE=1 ;;
		\?)
			msg error "Unknown option: $OPTARG"
			exit 2
			;;
		esac
	done
	shift $(($OPTIND - 1))

	local command="$1"

	if [ -z "$command" ]; then
		msg debug "No command provided."
		_show_help
		exit 1
	fi

	_ensure_dependencies
	_install_upsh

	msg debug "Running shell: ${bold}$current_shell${reset}"
	msg debug "Working dir: ${bold}$HSTNL_WORK_DIR${reset}"
	msg debug "Config dir:${bold}$HSTNL_CONF_DIR${reset}"
	msg debug "Script dir: ${bold}$SCRIPT_DIR${reset}"
	msg debug "up.sh path: ${bold}$UPSH${reset}"
	msg debug "Command provided: ${bold}$command${reset}"

	case "$command" in
	"status")
		if _vpn_status; then # Check VPN connection status
			_set_env
		fi
		;;
	"stop")
		if _vpn_status; then # Disconnect and clean-up if connected
			_vpn_disconnect
			_clean_up
			_unset_env
		fi
		;;
	"list")
		_list_config_files # Look for config files
		;;
	*)
		if ! _list_config_files >/dev/null 2>&1; then
			msg error "No .ovpn config files found in ${bold}'$HSTNL_CONF_DIR'${reset}'"
			exit 1
		fi

		if _vpn_status >/dev/null 2>&1; then
			msg success "Already connected to a VPN: ${bold}$lab${reset}"
			_set_env
			exit 0
		fi

		local vpn_config="$HSTNL_CONF_DIR/${command}.ovpn"

		if [ -f "$vpn_config" ]; then
			_vpn_connect "$vpn_config"
			_set_env
		else
			msg error "${bold}'${command}.ovpn'${reset} does not exist."
			_show_help
			exit 1
		fi
		;;
	esac
}

[[ $ANSI == 1 ]] && initialize_ansi
hstnl "$@"
