#!/bin/bash
echo WARNING: This script is setting up all the disks for SSD use, modify udev if needed!!!
echo WARNING: This script is setting up all the disks for SSD use, modify udev if needed!!!
echo WARNING: This script is setting up all the disks for SSD use, modify udev if needed!!!
# $1 read_ahead_kb
# $2 scheduler

#If we are root, do all the following, no idents as this is everything
if [ `id -u` -eq 0 ]; then 

if [ -z $1 ]; then rakb=16; else rabk=$1; fi
if [ -z $2 ]; then sched=noop; else sched=$2; fi

#AMAZON instances remove the cloud config
umount /dev/xvdb
sed -i '/cloudconfig/d' /etc/fstab

sed -i '/exit 0/d' /etc/rc.local
cat << EOF >> /etc/rc.local
#Will use madvise if available, if not will use never
if test -f /sys/kernel/mm/transparent_hugepage/enabled; then
   echo never > /sys/kernel/mm/transparent_hugepage/enabled
   echo madvise > /sys/kernel/mm/transparent_hugepage/enabled
fi
if test -f /sys/kernel/mm/transparent_hugepage/defrag; then
   echo never > /sys/kernel/mm/transparent_hugepage/defrag
   echo madvise > /sys/kernel/mm/transparent_hugepage/defrag
fi

exit 0
EOF

#disable SE linux
if [ -f /etc/selinux/config ]; then
sudo sed -i 's/enforcing/disabled/' /etc/selinux/config
sudo sed -i 's/permissive/disabled/' /etc/selinux/config
fi

#set keepalive and zone_reclaim_mode
sed -i '/net.ipv4.tcp_keepalive_time/d' /etc/sysctl.conf
sed -i '/vm.zone_reclaim_mode/d' /etc/sysctl.conf
cat << EOF >> /etc/sysctl.conf
net.ipv4.tcp_keepalive_time = 300
vm.zone_reclaim_mode = 0
EOF
sysctl -p

#set ulimits - for extensive microsharding these need to be huge
#set for all users, in multitenant, user may be mongodb or mongod
echo "* soft nofile 64000
* hard nofile 64000
* soft nproc unlimited
* hard nproc unlimited" > /etc/security/limits.conf
#various RHEL clones set things in limits.d, we don't want any of them
rm -rf /etc/security/limits.d/*

#set RA
#Note the scheduler is set to "noop", bare metal probably want to remove that/cfq
#For non-flash, rotational=1, ra should probably be adjusted too
cat << EOF > /etc/udev/rules.d/99-mongo-vm-devices.rules
SUBSYSTEM=="block", ACTION=="add|change", ATTR{bdi/read_ahead_kb}="${rakb}", ATTR{queue/scheduler}="${sched}", ATTR{queue/add_random}="0”, ATTR{queue/rotational}="0”, ATTR{queue/rq_affinity}="2"
EOF
else 
echo This script must be run as root
fi
