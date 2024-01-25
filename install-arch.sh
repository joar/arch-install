set -o errexit pipefail
(
  set -x;
  umount -R /mnt || true;
  cryptsetup close system || true;
)

pacman -Sy --noconfirm dialog

X_EFS_PATH="/boot"
export X_EFS_PATH

LUKS_PASSWORD="$(/arch-install/prompt-password.sh "Disk encryption password")" || (echo could not password; exit 1 )

ROOT_PASS="$(/arch-install/prompt-password.sh "root password")" || ( echo "failed to set pass"; exit 1;)
USERNAME="joar"
PASSWORD="$(/arch-install/prompt-password.sh "password for $USERNAME")" || ( echo "failed to set pass"; exit 1;)

(
set -x;
# Remove existing partitions
sgdisk --zap-all /dev/nvme0n1;

# Create partitions
sgdisk --clear \
  --new=1:0:+2GiB --typecode=1:ef00 --change-name=1:EFI \
  --new=2:0:0 --typecode=2:8300 --change-name=2:cryptsystem \
  /dev/nvme0n1;
)


# System
(
set -x; \
  echo "$LUKS_PASSWORD" | cryptsetup luksFormat --type luks2 --cipher aes-xts-plain64 /dev/disk/by-partlabel/cryptsystem \
  && echo "$LUKS_PASSWORD" | cryptsetup open /dev/disk/by-partlabel/cryptsystem system \
  && mkfs.btrfs --label system /dev/mapper/system \
  && mount -t btrfs LABEL=system /mnt \
  && btrfs subvolume create /mnt/@root \
  && btrfs subvolume create /mnt/@home \
  && btrfs subvolume create /mnt/@snapshots \
  && umount -R /mnt \
  && mount -t btrfs -o defaults,x-mount.mkdir,compress=zstd,ssd,noatime,subvol=@root LABEL=system /mnt \
  && mount -t btrfs -o defaults,x-mount.mkdir,compress=zstd,ssd,noatime,subvol=@home LABEL=system /mnt/home \
  && mount -t btrfs -o defaults,x-mount.mkdir,compress=zstd,ssd,noatime,subvol=@snapshots LABEL=system /mnt/.snapshots \
)

# EFI
(
set -x;
mkfs.fat -F32 -n EFI /dev/disk/by-partlabel/EFI \
  && mkdir -p /mnt"$X_EFS_PATH" \
  && mount LABEL=EFI /mnt"$X_EFS_PATH"
)
awk -i inplace '{ gsub(/#?ParallelDownloads\s*=.+$/, "ParallelDownloads=50"); }; { print }' /etc/pacman.conf

# Install system
(
set -x;
pacstrap /mnt \
  base \
  linux \
  linux-firmware \
  networkmanager \
  base-devel \
  btrfs-progs \
  gptfdisk \
  fish \
  sudo \
  ttf-dejavu \
  sbctl \
  intel-ucode \
  polkit \
  fish \
  pkgfile \
  git \
  efibootmgr \
  dialog \
  neovim \
  terminus-font \
  && genfstab -L -p /mnt > /mnt/etc/fstab \
)

cp -r /arch-install /mnt/arch-install
arch-chroot /mnt env ROOT_PASS="$ROOT_PASS" USERNAME="$USERNAME" PASSWORD="$PASSWORD" bash /arch-install/in-chroot.sh


(
set -x;
systemd-nspawn -b -D /mnt /arch-install/in-systemd-nspawn.sh
# TPM setup
# systemd-cryptenroll --tpm2-device=/dev/tpmrm0 --tpm2-pcrs=0+7 --tpm2-with-pin=yes /dev/disk/by-partlabel/cryptsystem
)

# DISK="/dev/disk/by-id/nvme-SKHynix_HFM512GD3HX015N_FJB6N580712306E47"
# mkdir -p /mnt/lukskey
# dd bs=512 count=8 if=/dev/urandom of=/mnt/lukskey/crypto_keyfile.bin
# chmod 600 /mnt/lukskey/crypto_keyfile.bin
# cryptsetup luksAddKey "$DISK-part3" $INST_MNT/lukskey/crypto_keyfile.bin
# chmod 700 $INST_MNT/lukskey
