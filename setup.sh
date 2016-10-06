#! /bin/bash

export LANG=C

SRC="/root/raspberrypi-audio-streaming"
FIRMWARE_VERSION="9e8f2d6f0c5afd54ab2018c7634785941f04ef91"

source ${SRC}/common.sh

function copy_file {
  mkdir -pv "$(dirname ${1})" || die "Failed to create directory structure for ${1}"
  cp -v "${SRC}${1}" "${1}" || die "Failed to copy file ${1}"
}

## Setup HifiBerry ##

apt-get update || die "Failed to update package list"
apt-get install -y rpi-update || die "Failed to install rpi-update"

rpi-update ${FIRMWARE_VERSION} || die "Execution of rpi-update failed"

# Disable onboard sound
sed -e '/dtparam=audio=on/ s/^#*/#/' -i /boot/config.txt || die "Failed to disable onboard sound"

# Enable hifiberry driver
echo "dtoverlay=hifiberry-dac" >> /boot/config.txt || die "Failed to enable hifiberry driver"

copy_file /etc/asound.conf

## Setup PulseAudio network streaming and publishing via Zeroconf ##

apt-get install -y --no-install-recommends pulseaudio pulseaudio-module-zeroconf  || die "Failed to install pulseaudio"

copy_file /etc/systemd/system/pulseaudio.service

systemctl enable pulseaudio.service || die "Failed to enable pulseaudio systemd unit"
usermod -a -G pulse-access pi || die "Failed to add user pi to pulse-access group"
usermod -a -G pulse-access root || die "Failed to add user root to pulse-access group"

echo "load-module module-native-protocol-tcp auth-anonymous=1" >> /etc/pulse/system.pa || die "Failed to configure pulseaudio"
echo "load-module module-zeroconf-publish" >> /etc/pulse/system.pa || die "Failed to configure pulseaudio"

sed -i 's/^load-module module-udev-detect$/load-module module-udev-detect tsched=0/' /etc/pulse/system.pa || die "Failed to configure pulseaudio"
sed -i 's/^use-ipv4=yes$/use-ipv4=no/' /etc/avahi/avahi-daemon.conf || die "Failed to configure avahi"

## Setup PulseAudio Bluetooth A2DP target ##

apt-get install -y --no-install-recommends pulseaudio-module-bluetooth || die "Failed to install pulseaudio bluetooth module"

echo "load-module module-bluetooth-policy" >> /etc/pulse/system.pa || die "Failed to configure pulseaudio"
echo "load-module module-bluetooth-discover" >> /etc/pulse/system.pa || die "Failed to configure pulseaudio"

copy_file /etc/bluetooth/audio.conf
copy_file /etc/bluetooth/main.conf
copy_file /usr/local/bin/a2dp-autoconnect
copy_file /etc/udev/rules.d/99-input.rules

chmod +x /usr/local/bin/a2dp-autoconnect || die "Failed to change permissions of a2dp-autoconnect script"

echo "Setup finished successfully!"