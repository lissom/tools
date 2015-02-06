#!/bin/bash
echo WARNING: This script by default is setting up all the disks for SSD use (These settings will not work well on direct attached spinning disks)
echo If only mongoD is being run on the machine then how the non-mongoD disks are setup is not relevant
# $1 read_ahead_kb
# $2 scheduler
# $3 rotational (spinning drive = 1; other = 0)
# $4 nr_requests

#If we are root, do all the following, no idents as this is everything
if [ `id -u` -eq 0 ]; then 

if [ -z $1 ]; then rakb=16; else rabk=$1; fi
if [ -z $2 ]; then sched=noop; else sched=$2; fi
if [ -z $3 ]; then rotate=0; else rotate=$3; fi
if [ -z $4 ]; then nr_requests=256; else nr_requests=$4; fi


#if dc doens't exist
log() { local x=$1 n=2 l=-1;if [ "$2" != "" ];then n=$x;x=$2;fi;while((x));do let l+=1 x/=n;done;echo $l; } 
#These factors very per system
tune_cpu() {
sed -i '/kernel.sched_latency_ns/d' /etc/sysctl.conf
sed -i '/kernel.sched_min_granularity_ns/d' /etc/sysctl.conf
cat << EOF >> /etc/sysctl.conf
#default = 6ms*(1+log2(ncpus)), 8 CPU = 24000000
kernel.sched_latency_ns=36000000
#default = 0.75ms*(1+log2(ncpus)), 8 CPU = 3000000
kernel.sched_min_granularity_ns = 5000000
EOF
sysctl -p
#chrt still needs to be used to change the scheduling: chrt -b -p 0 <PID>
}

tune_memory() {
sed -i '/vm.dirty_ratio/d' /etc/sysctl.conf
sed -i '/vm.dirty_background_ratio/d' /etc/sysctl.conf
sed -i '/vm.dirty_expire_centisecs/d' /etc/sysctl.conf
sed -i '/vm.swappiness/d' /etc/sysctl.conf
cat << EOF >> /etc/sysctl.conf
#throttle writes at dirty % memory
vm.dirty_ratio=70
#wake up pdflush when dirty pages exceed % memory
vm.dirty_background_ratio=5
#dirty data can stay in momory for X milis before flush
vm.dirty_expire_centisecs=30000
#Steal application in-active pages?  Zero for no
vm.swappiness=0
EOF
sysctl -p
}

tune_net() {
#http://www.slideshare.net/cpwatson/cpn302-yourlinuxamioptimizationandperformance
#Value of flow is determined by number of active connections. Setting 32768 is a good start for moderately loaded server.
sed -i '/net.core.rps_sock_flow_entries/d' /etc/sysctl.conf
cat << EOF >> /etc/sysctl.conf
net.core.rps_sock_flow_entries = 32768
EOF
#For a single queue device (as in the case of AWS instances), the value of two tunables should be the same.
#/sys/class/net/*/rps_flow_cnt
#/sys/class/net/eth?/queues/rx-0 rps_cpus=0xf It is set as a bitmask of CPUs. Disable when set to zero (means packets are processed on the interrupted CPU). Set to all CPU or CPUs that are part of the same NUMA node (large server). Setting value 0xf will cause CPU 0,1,2,3 to do network stack processing 
#For high speed systems consider excluding cpu processing the interrupt from processing packs
#cat /proc/irq/<IRQ>/smp_affinity
#cat /proc/interrupts
}

sed -i '/exit 0/d' /etc/rc.local
cat << EOF >> /etc/rc.local
#Standard Linux THP Settings
if test -f /sys/kernel/mm/transparent_hugepage/enabled; then
   echo never > /sys/kernel/mm/transparent_hugepage/enabled
fi
if test -f /sys/kernel/mm/transparent_hugepage/defrag; then
   echo never > /sys/kernel/mm/transparent_hugepage/defrag
fi
#RHEL + RHEL Clone systems
if test -f /sys/kernel/mm/redhat_transparent_hugepage/enabled; then
   echo never > /sys/kernel/mm/redhat_transparent_hugepage/enabled
fi
if test -f /sys/kernel/mm/redhat_transparent_hugepage/defrag; then
   echo never > /sys/kernel/mm/redhat_transparent_hugepage/defrag
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
sed -i '/kernel.pid_max/d' /etc/sysctl.conf
cat << EOF >> /etc/sysctl.conf
net.ipv4.tcp_keepalive_time = 300
vm.zone_reclaim_mode = 0
kernel.pid_max = 4194303
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
SUBSYSTEM=="block", ACTION=="add|change", ATTR{bdi/read_ahead_kb}="${rakb}", ATTR{queue/scheduler}="${sched}", ATTR{queue/add_random}="0", ATTR{queue/rotational}="${rotate}", ATTR{queue/rq_affinity}="2", ATTR{queue/nr_requests}="${nr_requests}"
EOF
else 
echo This script must be run as root
fi
