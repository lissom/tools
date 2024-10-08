#!/bin/bash
set -euxo pipefail 

# oracle download java page: https://www.oracle.com/java/technologies/javase-jdk16-downloads.html

bm=0
sudo apt update
sudo apt upgrade -y
apt dist-upgrade
sudo apt autoremove
sudo apt install flatpak
# sudo flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo


echo ttf-mscorefonts-installer msttcorefonts/accepted-mscorefonts-eula select true | sudo debconf-set-selections
sudo apt install -y ubuntu-restricted-extras

sudo apt install -y wireguard vim htop zip unzip sysstat screen openvpn nfs-common git tig meld chrome-gnome-shell \
default-jdk python2 gnome-tweaks dconf-editor sshfs pigz python3-venv cachefilesd clamav clamav-daemon ripgrep \
nvtop psensor apt-transport-https tree 7zip pipenv

# Clamav
# On access scanning may need lots of inodes
echo fs.inotify.max_user_watches=524288 | sudo tee -a /etc/sysctl.conf
sudo sysctl -p
echo 'X5O!P%@AP[4\PZX54(P^)7CC)7}$EICAR-STANDARD-ANTIVIRUS-TEST-FILE!$H+H*' > ~/clamav-testfile

sudo dd of=/etc/clamav/virusevent.d/notify.sh << 'EOF'
#!/bin/bash
# Check if virus was detected
if [ "$CLAM_VIRUSEVENT_VIRUSNAME" != "" ]; then
    # Generate notification
    ALERT="Signature detected by ClamAV: $CLAM_VIRUSEVENT_VIRUSNAME in $CLAM_VIRUSEVENT_FILENAME"
    
    # Send notification
    notify-send -i dialog-warning "Virus found!" "$ALERT"
fi
EOF
sudo chmod +x /etc/clamav/virusevent.d/notify.sh

sudo dd of=/etc/sudoers.d/clamav << EOF
clamav ALL=(ALL) NOPASSWD: /usr/bin/notify-send
EOF

if [ `clamscan ~/clamav-testfile` ]; then
echo Test sig failed
exit 1
fi


sudo ln -s /etc/clamav/clamd.conf /usr/local/etc/clamd.conf
sudo ln -s /etc/clamav/freshclam.conf /usr/local/etc/freshclam.conf
sudo ln -s /etc/clamav/virusevent.d /usr/local/etc/virusevent.d

echo "OnAccessMountPath /home
OnAccessPrevention yes
OnAccessExtraScanning yes
OnAccessIncludePath /var/www
OnAccessExcludeUname clamav
OnAccessExcludeRootUID true
VirusEvent /etc/clamav/virusevent.d/notify.sh" | sudo tee -a /etc/clamav/clamd.conf
# snaps are not regular files
for f in /home/*; do
  echo OnAccessExcludePath $f/snap | sudo tee -a /etc/clamav/clamd.conf
done

# Everything but VMs
sudo sed 's|OnAccessMaxFileSize.*|OnAccessMaxFileSize 5000M|' -i /etc/clamav/clamd.conf

echo '[Unit]
Description=ClamAV On Access Scanner
Requires=clamav-daemon.service
After=clamav-daemon.service

[Service]
ExecStartPre=/bin/bash -c "while [ ! -S /var/run/clamav/clamd.ctl ]; do sleep 1; done"
ExecStart=/usr/sbin/clamonacc -F --log=/var/log/clamav/access.log --fdpass
Restart=on-failure

[Install]
WantedBy=multi-user.target' | sudo tee /etc/systemd/system/clamav-onacc.service
sudo systemctl daemon-reload
sudo systemctl enable --now clamav-onacc.service

#Chrome
wget https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb -P /tmp
sudo sudo apt install /tmp/google-chrome-stable_current_amd64.deb

gsettings set org.gnome.shell.extensions.dash-to-dock isolate-workspaces true
gsettings set org.gnome.shell.extensions.dash-to-dock isolate-monitors true
gsettings set org.gnome.desktop.wm.keybindings move-to-workspace-left "['<Primary><Shift><Alt>Left']"
gsettings set org.gnome.desktop.wm.keybindings move-to-workspace-right "['<Primary><Shift><Alt>Right']"
gsettings set org.gnome.desktop.wm.keybindings move-to-workspace-up "['<Primary><Shift><Alt>Up']"
gsettings set org.gnome.desktop.wm.keybindings move-to-workspace-down "['<Primary><Shift><Alt>Down']"
#gsettings list-recursively org.gnome.desktop.wm.keybindings

#Firefox - the snap just stopped working
sudo snap remove firefox
sudo add-apt-repository ppa:mozillateam/ppa
echo '
Package: *
Pin: release o=LP-PPA-mozillateam
Pin-Priority: 1001
' | sudo tee /etc/apt/preferences.d/mozilla-firefox
echo 'Unattended-Upgrade::Allowed-Origins:: "LP-PPA-mozillateam:${distro_codename}";' | sudo tee /etc/apt/apt.conf.d/51unattended-upgrades-firefox
sudo apt install firefox -y

mkdir ~/.local/bin
echo '
#!/bin/bash
chmod -euo pipefail
swapfile=/swapfile
[ -e /swapfile1 ] && sudo swapoff ${swapfile}
sudo truncate -s 0 ${swapfile}
sudo chattr +C ${swapfile}
sudo fallocate -l 20G ${swapfile}
sudo chmod 0600 ${swapfile}
sudo mkswap ${swapfile}
sudo swapon ${swapfile}
' | tee ~/.local/bin/reset-swap
chmod +x ~/.local/bin/reset-swap

echo "pkill chrome" > ~/.bash_logout

[ ${bm:-0} -eq 1 ] || exit 0

#System utils
sudo apt install -y numactl numad
# sudo apt install virt-manager
# virsh net-autostart default
# xfsprogs mdadm lvm2 virtualbox

# after setting up screens
sudo cp ~/.config/monitors.xml /var/lib/gdm3/.config/

# btrfs snapshots
sudo apt install -y snapper snapper-gui
sudo snapper -c root create-config /
sudo snapper -c home create-config /home
function update_kv {
  sudo sed "/^$1/s/=.*$/=\"$2\"/" -i $3
}
for f in /etc/snapper/configs/root /etc/snapper/configs/home; do
update_kv TIMELINE_LIMIT_HOURLY 5 $f
update_kv TIMELINE_LIMIT_DAILY 7 $f
update_kv TIMELINE_LIMIT_WEEKLY 2 $f
update_kv TIMELINE_LIMIT_MONTHLY 1 $f
update_kv TIMELINE_LIMIT_YEARLY 0 $f
done
sudo systemctl enable --now snapper-timeline.timer
sudo systemctl enable --now snapper-cleanup.timer

if [ ! `sudo btrfs subvolume list / | grep @cache` ]; then
root_device=$(mount | grep ' / ' | cut -f1 -d' ')
root_mount_by=$(cat /etc/fstab  | grep ' / ' | grep -E 'subvol=@([[:space:]]|,)' | cut -f1 -d' ')
sudo mount $root_device /mnt
sudo btrfs sub create /mnt/@cache
sudo umount /mnt
sudo mkdir -p /cache
echo ${root_mount_by} /cache btrfs defaults,nodatacow,subvol=@cache 0 3 | sudo tee -a /etc/fstab
sudo mount -o subvol=@cache $device /cache
umount $root_device
fi
mkdir -p /cache/fscache

sudo sed 's/#RUN=yes/RUN=yes/' -i /etc/default/cachefilesd 
sudo sed 's|/var/cache/fscache|/cache/fscache|' -i /etc/cachefilesd.conf
sudo systemctl enable --now cachefilesd # nfs -o fsc, sshfs cache=yes

true_path=`which true`
echo "[Unit]
Description=Help Chrome close gracefully

[Service]
Type=oneshot
RemainAfterExit=yes
Restart=never
ExecStart=${true_path}
ExecStop=/usr/bin/killall chrome --wait

[Install]
WantedBy=default.target
" | sudo tee /etc/systemd/user/shutdown-chrome.service

sudo systemctl daemon-reload
sudo systemctl --global enable shutdown-chrome.service

sudo mkdir -p /opt/local/systemd
s_exec_path=/opt/local/systemd/force-unmount
sudo dd of=${s_exec_path} << 'EOF'
#/bin/bash
for m_path in $(mount | grep nfs | cut -d' ' -f3); do
/usr/bin/lsof -N $m_path | awk 'NR>1 {print $2}' | xargs -r kill
/usr/bin/umount ${m_path}
done
[ ! `mount | grep nfs` ] && exit 0
for _ in {1..10}; do
do_break=1
for m_path in $(mount | grep nfs | cut -d' ' -f3); do
[ `/usr/bin/lsof -N $m_path | awk 'NR>1 {print $2}' | wc -l` -ne 0 ] && do_break=0
done
[ $do_break -eq 1 ] && break
sleep 1s
done
for m_path in $(mount | grep nfs | cut -d' ' -f3); do
/usr/bin/lsof -N $m_path | awk 'NR>1 {print $2}' | xargs -r kill -9
/usr/bin/umount ${m_path} -lfr
done
EOF
sudo chmod +x ${s_exec_path}

service=shutdown-nfs
s_path=/opt/local/systemd/$service.service
sudo dd of=${s_path} << EOF
[Unit]
Description=Terminate nfs mounts
DefaultDependencies=no
After=network-online.target wg-quick@wg0
Requires=network-online.target wg-quick@wg0

[Service]
ExecStart=/bin/true
RemainAfterExit=yes
ExecStop=${s_exec_path}

[Install]
WantedBy=network-online.target
EOF

sudo ln -s ${s_path} /etc/systemd/system/${service}.service
sudo systemctl enable --now ${service}

echo "alias rcp='rsync -chavzP --stats'" >> ~/.bashrc

exit 0

cd ~/
wget https://apt.llvm.org/llvm.sh
chmod +x llvm.sh
sudo llvm.sh 19
sudo apt install libstdc++-12-dev # 22.04

# gnome extensions
https://extensions.gnome.org/extension/906/sound-output-device-chooser/
https://extensions.gnome.org/extension/1485/workspace-matrix/

powerprofilesctl set performance
sudo apt install linux-tools-common linux-tools-`uname -r`
cpupower-gui
cpupower frequency-info
sudo cpupower frequency-set -g performance

https://www.sophos.com/en-us/products/free-tools/sophos-antivirus-for-linux.aspx

Remina: 
https://kbdlayout.info/kbdusx/virtualkeys
Preferences->RDP
0x3a=0x1D,0x1D=0x3a
