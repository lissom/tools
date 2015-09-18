#!/bin/bash
#Ubuntu
sudo apt-get install linux-firmware-nonfree compizconfig-settings-manager unity-tweak-tool

#Video cards
#sudo apt-get install nvidia-current
#sudo apt-get install fglrx fglrx-updates 

#App armor
#sudo invoke-rc.d apparmor kill
#sudo update-rc.d -f apparmor remove

#System utils
sudo apt-get install htop zip unzip 

#Java
sudo add-apt-repository ppa:webupd8team/java
sudo apt-get update
sudo apt-get install oracle-java8-installer


sudo apt-get -f install && sudo apt-get autoremove && sudo apt-get -y autoclean && sudo apt-get -y clean

