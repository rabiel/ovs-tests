#!/bin/bash
#
#  desc: TODO
#
#  test: TODO
#

NIC=${1:-ens5f0}

my_dir="$(dirname "$0")"
. $my_dir/common.sh

reset_tc_nic $NIC
rep=${NIC}_0
if [ -e /sys/class/net/$rep ]; then
    reset_tc_nic $rep
fi

local_ip="2.2.2.2"
remote_ip="2.2.2.3"
dst_mac="e4:1d:2d:fd:8b:02"
flag=skip_sw
dst_port=1234
id=98

function disable_sriov_and_multipath() {
    title "- Disable SRIOV"
    echo 0 > /sys/class/net/$NIC/device/sriov_numvfs
    echo 0 > /sys/class/net/$NIC2/device/sriov_numvfs

    title "- Disable multipath"
    disable_multipath || err "Failed to disable multipath"
}

function enable_multipath_and_sriov() {
    title "- Enable multipath"
    disable_multipath
    enable_multipath || err "Failed to enable multipath"

    title "- Enable SRIOV"
    echo 2 > /sys/class/net/$NIC/device/sriov_numvfs
    echo 2 > /sys/class/net/$NIC2/device/sriov_numvfs
}

function cleanup() {
    ip link del dev vxlan1 2> /dev/null
    ip n del ${remote_ip} dev $NIC 2>/dev/null
    ip n del ${remote_ip6} dev $NIC 2>/dev/null
    ifconfig $NIC down
    ip addr flush dev $NIC
}

function config_vxlan() {
    ip link add vxlan1 type vxlan id $id dev $NIC dstport $dst_port
    ip link set vxlan1 up
}

function add_vxlan_rule() {
    local local_ip="$1"
    local remote_ip="$2"

    echo "local_ip $local_ip remote_ip $remote_ip"

    # tunnel key set
    ifconfig $NIC up
    reset_tc $NIC
    reset_tc $REP

    cmd="tc filter add dev $REP protocol arp parent ffff: \
        flower dst_mac $dst_mac $flag \
        action tunnel_key set \
            id $id src_ip ${local_ip} dst_ip ${remote_ip} dst_port ${dst_port} \
        action mirred egress redirect dev vxlan1"
    echo $cmd
    $cmd
}


# multipath enabled, sriov mode, add encap rule
function test_add_nic_rule_in_sriov() {
    disable_sriov_and_multipath
    enable_multipath_and_sriov
    ifconfig $NIC up
    cleanup
}

# multipath enabled, switchdev mode on pf0 only, add encap rule
function test_add_esw_rule_only_pf0_in_switchdev() {
    disable_sriov_and_multipath
    enable_multipath_and_sriov
    enable_switchdev
    config_vxlan
    add_vxlan_rule $local_ip $remote_ip
    cleanup
}


cleanup
test_add_nic_rule_in_sriov
test_add_esw_rule_only_pf0_in_switchdev

test_done