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
systemctl enable ssh.service

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

sed  -i '/^exit 0$/i hciconfig hci0 piscan' /etc/rc.local
sed  -i '/^exit 0$/i hciconfig hciconfig hci0 sspmode 1' /etc/rc.local
sed  -i '/^exit 0$/i /usr/local/bin/simple-agent &' /etc/rc.local

chmod +x /usr/local/bin/* || die "Failed to make scripts executable"

## Make filesystem readonly ##

log_info "Preparing readonly filesystem..."
copy_file /etc/fstab
rm -rf /var/lib/dhcp/ /var/spool /var/lock /etc/resolv.conf || die "Failed to remove files"
ln -s /tmp /var/lib/dhcp || die "Failed to create link"
ln -s /tmp /var/spool || die "Failed to create link"
ln -s /tmp /var/lock || die "Failed to create link"
ln -s /tmp/resolv.conf /etc/resolv.conf || die "Failed to create link"

# Create a 10 MB image file in /boot which will be mounted via loop device to /var/lib/bluetooth
IMG_FILE="/boot/bt-persist.img"
dd if=/dev/zero of=${IMG_FILE} bs=1MB count=10 || die "Failed to create image file"
mkfs.ext4 -F ${IMG_FILE} || die "Failed to format image file"

# Create necessary mountpoints
mkdir -vp /var/lib/pulse /var/lib/bluetooth

#sed  -i '/^exit 0$/i chmod 777 /tmp' /etc/rc.local

echo "Setup finished successfully!"
