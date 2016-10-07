#! /bin/bash
## Arguments:
## $1: sd card device

SRC_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

TARGET_DEVICE="${1}"

RASPIAN_BUILD_DATE="2016-09-23"
RASPIAN_RELEASE_DATE="2016-09-28"

IMAGE_PACKAGE="${RASPIAN_BUILD_DATE}-raspbian-jessie-lite.zip"
SHA1_SUM="3a34e7b05e1e6e9042294b29065144748625bea8"
RASPBIAN_BASE_IMAGE_URL="http://downloads.raspberrypi.org/raspbian_lite/images/raspbian_lite-${RASPIAN_RELEASE_DATE}/${IMAGE_PACKAGE}"
DOWNLOAD_DIR="$HOME/Downloads"
WORKING_DIR=/tmp/raspberrypi-audio-streaming
MOUNT_TARGET=${WORKING_DIR}/mount
TARGET_SRC_DIR="/root/raspberrypi-audio-streaming"
MOUNTED_TARGET_SRC_DIR="${MOUNT_TARGET}/root/raspberrypi-audio-streaming"

source ./common.sh

function cleanup {
  umount --recursive ${MOUNT_TARGET} || echo "Failed to unmount target device fs"
  kpartx -d ${TARGET_DEVICE} || die "Could not delete partition mappings"
}

function cleanup_and_die {
  cleanup
  die "${1}"
}

function make_partition {
    parted -s "$1" unit s mkpart primary "$2" "$3"
}

if [ "${USER}" != "root" ]; then
  die "Need to run as root!"
fi

if [ ! -b "${TARGET_DEVICE}" ]; then
  die "Given argument is not a valid block device"
fi
TARGET_DEVICE_BASENAME=$(basename ${TARGET_DEVICE})

echo "Are you sure you want to install to ${TARGET_DEVICE}? ALL DATA ON IT WILL BE LOST!"
read -p "If you are absolutely sure, answer with uppercase yes: " choice
case "$choice" in
  YES ) echo "Okay, continuing...";;
  * ) exit 0;;
esac

rm -rf ${WORKING_DIR} || die "Failed to cleanup working directory"

mkdir -p "${DOWNLOAD_DIR}" || die "Failed to create required directories"
mkdir -p "${WORKING_DIR}" || die "Failed to create required directories"
mkdir -p ${MOUNT_TARGET} || die "Failed to create required directories"

cd "$DOWNLOAD_DIR"

if [ ! -f ${IMAGE_PACKAGE} ]; then
  log_info "Downloading raspbian lite image..."
  curl -L -o ${IMAGE_PACKAGE} ${RASPBIAN_BASE_IMAGE_URL} || die "Failed to download package"
else
  log_info "Found existing raspian lite image, skipping download."
fi

log_info "Checking integrity of downloaded file..."
echo "${SHA1_SUM} ${IMAGE_PACKAGE}" | sha1sum -c - || die "Checksum did not match"

log_info "Check was successful."
log_info "Unpacking file..."
unzip "${IMAGE_PACKAGE}" -d ${WORKING_DIR} || die "Failed to unzip package"
log_info "Unpacking complete."

IMAGE_FILE="${IMAGE_PACKAGE/%zip/img}"

cd "${WORKING_DIR}"
log_info "Copying image to sdcard..."
dd bs=4M if="${IMAGE_FILE}" of="${TARGET_DEVICE}" || die "Failed to copy image to sd card"
sync

log_info "Creating extra partition..."
make_partition "${TARGET_DEVICE}" $(parted -m ${TARGET_DEVICE} unit s print free | grep "free;" | head -n 1 | awk -F':' '{print $2 " " $3}')

log_info "Creating partition mappings..."
PART_1_DEV="/dev/mapper/$(kpartx -l ${TARGET_DEVICE} | awk 'NR == 1 {print $1; exit}')"
PART_2_DEV="/dev/mapper/$(kpartx -l ${TARGET_DEVICE} | awk 'NR == 2 {print $1; exit}')"
PART_3_DEV="/dev/mapper/$(kpartx -l ${TARGET_DEVICE} | awk 'NR == 3 {print $1; exit}')"
kpartx -as ${TARGET_DEVICE} || die "Could not add partition mappings"

log_info "Formatting extra partition..."
mkfs.ext4 -F "${PART_3_DEV}" || die "Failed to format extra partition"

log_info "Mounting target filesystems"

mount "${PART_2_DEV}" "${MOUNT_TARGET}" || cleanup_and_die "Could not mount target device root fs"
mount "${PART_1_DEV}" "${MOUNT_TARGET}/boot" || cleanup_and_die "Could not mount target device boot fs"
mkdir -vp "${MOUNT_TARGET}/var/lib/pulse" "${MOUNT_TARGET}/var/lib/bluetooth"
mount "${PART_3_DEV}" "${MOUNT_TARGET}/var/lib/bluetooth" || cleanup_and_die "Could not mount bluetooth fs"

# Copy dns configuration
cp -L /etc/resolv.conf "${MOUNT_TARGET}/etc/"

log_info "Performing setup inside target filesystem..."
proot -q qemu-arm -r ${MOUNT_TARGET} \
  -b ${SRC_DIR}:${TARGET_SRC_DIR} \
  -b /dev \
  -b /sys \
  -b /proc \
  -w ${TARGET_SRC_DIR} "./setup.sh" || cleanup_and_die "Setup failed"

log_info "Unmounting and cleaning up..."
cleanup
