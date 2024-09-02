#/bin/bash
set -euxo pipefail
root_mount_by=$(cat /etc/fstab  | grep ' / ' | grep -E 'subvol=@([[:space:]]|,)' | cut -f1 -d' ')
sudo btrfs subvolume snapshot / /@
sudo btrfs subvolume create /@home
sudo mv /@/home/* /@home/
sed -e '|" / " |s|^#*|#|' -i /etc/fstab
echo "${root_mount_by} / btrfs defaults,compress=zstd:1,subvol=@ 0 1
${root_mount_by} /home btrfs defaults,compress=zstd:1,subvol=@home 0 2" | sudo tee -a /etc/fstab

sudo sed 's|GRUB_TIMEOUT_STYLE=.*|GRUB_TIMEOUT_STYLE=menu|' -i /etc/default/grub
sudo sed 's|GRUB_TIMEOUT=.*|GRUB_TIMEOUT=10|' -i /etc/default/grub
sudo update-grub

echo "On next boot:
on the linux line
linux     /@/boot/...
near the end add:
rootflags=subvol=@
so that it looks like:
ro rootflags=subvol=@ quiet splash
modify initrd:
initrd   /@/boot/...

On reboot verify subvol=@ is being used
mount | grep ' / ' | grep subvol=@
"

exit 0

# After restart
# Permanently setup new boot
mount | grep ' / '
mount | grep ' / ' | grep subvol=@ || exit 1
sudo update-grub
grub-install --efi-directory=/boot/efi
reboot

# Remove root
root_device=$(mount | grep ' / ' | cut -f1 -d' ')
sudo mount $root_device /mnt
cd /mnt
ls | grep "^@"
ls | grep "^@" || exit 1
shopt -s extglob
sudo rm -rf !(@*)  
shopt -u extglob
sudo umount $root_device

