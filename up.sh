#!/bin/sh
HSTNL_WORK_DIR=$1

echo "$ifconfig_local" > "$HSTNL_WORK_DIR/lhost"
echo "$route_vpn_gateway" > "$HSTNL_WORK_DIR/vpn_gw_ip"
