#!/bin/bash

if [ `id -u` -ne 0 ]; then 
  #attempt to promote to su, works on amazon boxes etc
  sudo -n su -
  if [ `id -u` -ne 0 ]; then 
    echo
    echo ** This script must be ran as root, unable to sudo su - to root. **
    echo
    #abort script if we aren't root, do nothing in interactive shell
    case $- in
    *i*)
      sleep 2
    ;;
    *)
      exit
    ;;
    esac
  fi
fi

function do_fixes {
   
#AMAZON instances remove the cloud config
umount /dev/xvdb
sed -i '/cloudconfig/d' /etc/fstab

sudo cat << EOF >> /etc/rc.local
#!/bin/sh -e

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

#disable NUMA
#assumes Amazon linux
sed -i '/^kernel/ s/$/ numa=off/g' /etc/grub.conf
#assumes ubuntu
sed -i '/^kernel/ s/$/ numa=off/g' /boot/grub/menu.lst
sed -i '/^kernel/ s/$/ apparmor=0/g' /boot/grub/menu.lst

#disable SE linux
#this needs to be updated to change anything to disabled, permissive sucks to (still does work)
if [ -f /etc/selinux/config ]; then
sudo sed -i 's/enforcing/disabled/' /etc/selinux/config
fi

#set keepalive and zone_reclaim_mode
cat <<EOF> /etc/sysctl.conf
net.ipv4.tcp_keepalive_time = 300
vm.zone_reclaim_mode = 0
EOF
sysctl -p

#set ulimits
echo "* soft nofile 64000
* hard nofile 64000
* soft nproc 32000
* hard nproc 32000" > /etc/security/limits.conf
#various RHEL clones set things in limits.d, we don't want any of them
rm -rf /etc/security/limits.d/*

#set RA
#NOTE: On Amazon read_ahead_kb is getting translated to 2x for RA (becuause SSZ = 512?)
cat <<EOF>> /etc/udev/rules.d/51-ec2-hvm-devices.rules
SUBSYSTEM=="block", ACTION=="add|change", ATTR{bdi/read_ahead_kb}="16", ATTR{queue/scheduler}="noop"
EOF

}

if [ `id -u` -eq 0 ]; then 
  do_fixes
fi
