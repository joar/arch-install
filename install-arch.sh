set -o errexit pipefail

pacman -Sy --noconfirm dialog

LUKS_PASSWORD="$(dialog --stdout --passwordbox "Disk encryption password" 0 0)"

LUKS_PASSWORD_2="$(dialog --stdout --passwordbox "Confirm disk encryption password" 0 0)"

if ! test "$LUKS_PASSWORD" = "$LUKS_PASSWORD_2"; then
  echo "Passwords do not match"
  exit 2
fi

# Remove existing partitions
sgdisk --zap-all /dev/nvme0n1

# Create partitions
sgdisk --clear \
  --new=1:0:+2GiB --typecode=1:ef00 --change-name=1:EFI \
  --new=2:0:+32GiB --typecode=2:8200 --change-name=2:cryptswap \
  --new=3:0:0 --typecode=3:8300 --change-name=3:cryptsystem /dev/nvme0n1


# Swap
(
set -x; \
  cryptsetup open --type plain --key-file /dev/urandom /dev/disk/by-partlabel/cryptswap swap \
  && mkswap --label swap /dev/mapper/swap \
  && swapon -L swap
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
  && mkdir -p /mnt/efi \
  && mount LABEL=EFI /mnt/efi
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
  && genfstab -L -p /mnt > /mnt/etc/fstab \
  && awk -i inplace '{ gsub(/LABEL=swap/, "/dev/mapper/swap") }; { print }' /mnt/etc/fstab \
  && echo "swap /dev/disk/by-partlabel/cryptswap /dev/urandom swap,offset=2048,cipher=aes-xts-plain64,size=256" > /mnt/etc/crypttab
)


arch-chroot /mnt
set -x
set -o errexit
# In chroot
awk -i inplace '{ gsub(/#?ParallelDownloads\s*=.+$/, "ParallelDownloads=50"); }; { print }' /etc/pacman.conf
ln -sf /usr/share/zoneinfo/Europe/Stockholm /etc/localtime
hwclock --systohc

# Locale
cat > /etc/locale.gen <<EOF
sv_SE.UTF-8 UTF-8
en_US.UTF-8 UTF-8
EOF
locale-gen

cat > /etc/locale.conf <<EOF
LANG=en_US.UTF-8
LC_TIME=sv_SE.UTF-8
LC_PAPER=sv_SE.UTF-8
LC_MONETARY=sv_SE.UTF-8
LC_MEASUREMENT=sv_SE.UTF-8
LC_NAME=sv_SE.UTF-8
LC_NUMERIC=sv_SE.UTF-8
LC_TELEPHONE=sv_SE.UTF-8
LC_ADDRESS=sv_SE.UTF-8
EOF

awk -i inplace '{ gsub(/^HOOKS=.*$/, "HOOKS=(base systemd plymouth modconf keyboard block filesystems btrfs encrypt fsck)") }; { print }' /etc/mkinitcpio.conf

cat > /etc/kernel/cmdline <<EOF
fbcon=nodefer rw rd.luks.allow-discards quiet bgrt_disable root=LABEL=system rootflags=subvol=@root,rw splash vt.global_cursor_default=0
EOF

cat > /etc/crypttab.initramfs <<EOF
system /dev/disk/by-partlabel/cryptsystem none timeout=180,tpm2-device=auto
EOF

sbctl create-keys
sbctl bundle -s /efi/main.efi



efibootmgr --create --disk /dev/nvme0n1 --part 1 --label "Arch Linux" --loader 'main.efi' --unicode

# Set root pass
(
ROOT_PASS_2="nothing"
until test "$ROOT_PASS" = "$ROOT_PASS_2"; do
  ROOT_PASS="$(dialog --stdout --passwordbox "Root password" 0 0)"
  ROOT_PASS_2="$(dialog --stdout --passwordbox "Confirm root password" 0 0)"

  if ! test "$ROOT_PASS" = "$ROOT_PASS_2"; then
    echo "Root passwords does not match"
  fi
done

passwd <<<"$(printf '%s\n' "$ROOT_PASS" "$ROOT_PASS_2")"
)

# Set up user
USERNAME="joar"
(
useradd -m -G wheel,storage,power -g users -s/usr/bin/fish "$USERNAME"
PASSWORD_2="invalid"
until test "$PASSWORD" = "$PASSWORD_2"; do
  PASSWORD="$(dialog --stdout --passwordbox "password for $USERNAME" 0 0)"
  PASSWORD_2="$(dialog --stdout --passwordbox "Confirm password for $USERNAME" 0 0)"

  if ! test "$PASSWORD" = "$PASSWORD_2"; then
    echo "Passwords does not match"
  fi
done

passwd "$USERNAME" <<<"$(printf '%s\n' "$PASSWORD" "$PASSWORD_2")"
)

# Allow sudo
(
awk -i inplace '{ gsub(/^# %wheel ALL=.*$/, "%wheel ALL=(ALL:ALL) ALL") }; { print }' /etc/sudoers
sudo -u "$USERNAME" -i
)

# Install pikaur
(
mkdir -p git
cd git
git clone https://aur.archlinux.org/pikaur.git
cd pikaur
makepkg -fsri
)

reflector --protocol https --latest 20 --ipv4 --country se,no,dk,fi --sort country

# Exit sudo impersonation
# exit

# Install plymouth-git
pikaur -Sy plymouth-git


plymouth-set-default-theme -R spinner
sbctl generate-bundles -s


# TPM setup
systemd-cryptenroll --tpm2-device=list
systemd-cryptenroll --tpm2-device=/dev/tpmrm0 --tpm2-pcrs=0+7 --tpm2-with-pin=yes /dev/disk/by-partlabel/cryptsystem


# DISK="/dev/disk/by-id/nvme-SKHynix_HFM512GD3HX015N_FJB6N580712306E47"
# mkdir -p /mnt/lukskey
# dd bs=512 count=8 if=/dev/urandom of=/mnt/lukskey/crypto_keyfile.bin
# chmod 600 /mnt/lukskey/crypto_keyfile.bin
# cryptsetup luksAddKey "$DISK-part3" $INST_MNT/lukskey/crypto_keyfile.bin
# chmod 700 $INST_MNT/lukskey
