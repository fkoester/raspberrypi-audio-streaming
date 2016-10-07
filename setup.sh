#! /bin/bash

export LANG=C

SRC="/root/raspberrypi-audio-streaming"
FIRMWARE_VERSION="9063f3eefb3469fcf2e9181aa623d2ca4908a675"

source ${SRC}/common.sh

function copy_file {
  mkdir -pv "$(dirname ${1})" || die "Failed to create directory structure for ${1}"
  cp -v "${SRC}${1}" "${1}" || die "Failed to copy file ${1}"
}

## Setup HifiBerry ##

log_info "Updating package list..."
apt-get update || die "Failed to update package list"
log_info "Installing rpi-update..."
apt-get install -y rpi-update || die "Failed to install rpi-update"

log_info "Enabling SSH server..."
dpkg-reconfigure openssh-server || die "Failed to setup ssh server"
systemctl enable ssh.service || die "Failed to setup ssh server"

log_info "Running rpi-update..."
rpi-update ${FIRMWARE_VERSION} || die "Execution of rpi-update failed"

log_info "Configuring sound drivers..."

# Disable onboard sound
sed -e '/dtparam=audio=on/ s/^#*/#/' -i /boot/config.txt || die "Failed to disable onboard sound"

# Enable hifiberry driver
echo "dtoverlay=hifiberry-dac" >> /boot/config.txt || die "Failed to enable hifiberry driver"

copy_file /etc/asound.conf

## Setup PulseAudio network streaming and publishing via Zeroconf ##

log_info "Installing PulseAudio and it's zeroconf modules..."
apt-get install -y --no-install-recommends pulseaudio pulseaudio-module-zeroconf  || die "Failed to install pulseaudio"

log_info "Setting up PulseAudio..."
copy_file /etc/systemd/system/pulseaudio.service

systemctl enable pulseaudio.service || die "Failed to enable pulseaudio systemd unit"
usermod -a -G pulse-access pi || die "Failed to add user pi to pulse-access group"
usermod -a -G pulse-access root || die "Failed to add user root to pulse-access group"

echo "load-module module-native-protocol-tcp auth-anonymous=1" >> /etc/pulse/system.pa || die "Failed to configure pulseaudio"
echo "load-module module-zeroconf-publish" >> /etc/pulse/system.pa || die "Failed to configure pulseaudio"

log_info "Configuring Avahi..."
sed -i 's/^load-module module-udev-detect$/load-module module-udev-detect tsched=0/' /etc/pulse/system.pa || die "Failed to configure pulseaudio"
sed -i 's/^use-ipv4=yes$/use-ipv4=no/' /etc/avahi/avahi-daemon.conf || die "Failed to configure avahi"

## Setup PulseAudio Bluetooth A2DP target ##

log_info "Installing PulseAudio bluetooth modules..."
apt-get install -y --no-install-recommends pulseaudio-module-bluetooth python-gobject python-dbus || die "Failed to install pulseaudio bluetooth module"

echo "load-module module-bluetooth-policy" >> /etc/pulse/system.pa || die "Failed to configure pulseaudio"
echo "load-module module-bluetooth-discover" >> /etc/pulse/system.pa || die "Failed to configure pulseaudio"

log_info "Configuring Bluetooth..."
copy_file /etc/bluetooth/main.conf
copy_file /usr/local/bin/simple-agent
copy_file /usr/local/bin/configure-bluetooth-device.sh
copy_file /etc/systemd/system/bluetooth-simple-agent.service
copy_file /etc/systemd/system/configure-bluetooth-device.service

chmod +x /usr/local/bin/* || die "Failed to make scripts executable"

systemctl enable configure-bluetooth-device.service || die "Failed to enable configure bt device systemd unit"
systemctl enable bluetooth-simple-agent.service || die "Failed to enable simple-agent systemd unit"

## Make filesystem readonly ##

log_info "Preparing readonly filesystem..."
copy_file /etc/fstab
rm -rf /var/lib/dhcp/ /var/spool /var/lock /etc/resolv.conf || die "Failed to remove files"
ln -s /tmp /var/lib/dhcp || die "Failed to create link"
ln -s /tmp /var/spool || die "Failed to create link"
ln -s /tmp/resolv.conf /etc/resolv.conf || die "Failed to create link"
ln -s /run/lock /var/lock || die "Failed to create link"
ln -sf /proc/mounts /etc/mtab || die "Failed to create link"

# Disable services that would fail on ro but are not needed anyways
systemctl disable apply_noobs_os_config.service
systemctl disable resize2fs_once.service

systemctl mask systemd-rfkill@rfkill0.service
systemctl mask systemd-rfkill@rfkill1.service

systemctl mask systemd-random-seed.service
# Somehow masking is not enough for that one, so remove it entirely.
rm -fv /lib/systemd/system/systemd-random-seed.service

echo "Setup finished successfully!"
