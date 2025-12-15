#!/bin/bash
/usr/sbin/nvme set-feature /dev/nvme0n1 -f 2 -v 2
sleep 30
echo powersupersave > /sys/module/pcie_aspm/parameters/policy
