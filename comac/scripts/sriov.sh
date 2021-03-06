#!/bin/bash

# Copyright (c) 2019 Intel Corporation
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# copied from https://github.com/clearlinux/cloud-native-setup/blob/master/clr-k8s-examples/9-multi-network/systemd/sriov.sh

set -o errexit
set -o pipefail
set -o nounset
set -x

OPTIND=1
bind="false"

while getopts ":b" opt; do
	case ${opt} in
	b)
		bind="true"
		;;
	\?)
		echo "Usage: sriov.sh [-b] ens785f0 ens785f1 ..."
		echo "-b	Bind to vfio-pci"
		exit
		;;
	esac
done
shift $((OPTIND - 1))

setup_pf() {
	local pf=$1
	local num_vfs

	echo "Resetting PF $pf"
	echo 0 | tee /sys/class/net/"$pf"/device/sriov_numvfs
	num_vfs=$(cat /sys/class/net/"$pf"/device/sriov_totalvfs)
	echo "Enabling $num_vfs VFs for $pf"
	echo "$num_vfs" | tee /sys/class/net/"$pf"/device/sriov_numvfs
	ip link set "$pf" up
	sleep 1
}

vfio_bind() {
	local pf=$1
	local pfpci
	local num_vfs

	pfpci=$(readlink /sys/devices/pci*/*/*/net/"$pf"/device | awk '{print substr($1,10)}')
	num_vfs=$(cat /sys/class/net/"$pf"/device/sriov_numvfs)

	local vfpci
	local mac
	for ((idx = 0; idx < num_vfs; idx++)); do
                #Some drivers does not support state change of VF
		#ip link set dev $pf vf $idx state enable

		local vfn="virtfn$idx"
		# shellcheck disable=SC2012
		vfpci=$(ls -l /sys/devices/pci*/*/"$pfpci" | awk -v vfn=$vfn 'vfn==$9 {print substr($11,4)}')
		# Capture and set MAC of the VF before unbinding from linux, for later use in CNI
		mac=$(cat /sys/bus/pci*/*/"$vfpci"/net/*/address)
		ip link set dev "$pf" vf $idx mac "$mac"
		# Bind VF to vfio-pci
		echo "$vfpci" >/sys/bus/pci*/*/"$vfpci"/driver/unbind
		echo "vfio-pci" >/sys/devices/pci*/*/"$vfpci"/driver_override
		echo "$vfpci" >/sys/bus/pci/drivers/vfio-pci/bind
	done
}

for pf in "$@"; do
	setup_pf "$pf"
        if [ $bind ]; then vfio_bind "$pf"; fi
done
