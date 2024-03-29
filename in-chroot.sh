# In chroot
X_EFS_PATH="${X_EFS_PATH:?"Missing X_EFS_PATH"}"

ROOT_PASS="${ROOT_PASS:?}"
USERNAME="${USERNAME:?}"
PASSWORD="${PASSWORD:?}"
export PASSWORD USERNAME ROOT_PASS

set -x
set -o errexit
awk -i inplace '{ gsub(/#?ParallelDownloads\s*=.+$/, "ParallelDownloads=50"); }; { print }' /etc/pacman.conf
ln -sf /usr/share/zoneinfo/Europe/Stockholm /etc/localtime
hwclock --systohc

cat > /etc/vconsole.conf <<EOF
KEYMAP=dvorak-sv-a1
FONT=Lat2-Terminus16
EOF

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

awk -i inplace '{ gsub(/^HOOKS=.*$/, "HOOKS=(base systemd autodetect modconf kms keyboard sd-vconsole block btrfs sd-encrypt filesystems fsck plymouth)") }; { print }' /etc/mkinitcpio.conf
grep -E '^HOOKS=' /etc/mkinitcpio.conf

X_KERNEL_OPTS="fbcon=nodefer rw rd.luks.allow-discards quiet bgrt_disable root=LABEL=system rootflags=subvol=@root,rw splash"

cat > /etc/kernel/cmdline <<EOF
$X_KERNEL_OPTS
EOF

cat > /etc/crypttab.initramfs <<EOF
system /dev/disk/by-partlabel/cryptsystem none timeout=180,tpm2-device=auto
EOF

# bootctl
#
efibootmgr | grep 'Linux Boot Manager' | awk '{ print $1 }' | sed -r 's/Boot([^*]{4})\*/\1/' | xargs --no-run-if-empty --max-args 1 efibootmgr --delete-bootnum --bootnum
bootctl install
cat > /boot/loader/entries/arch.conf <<EOF
title     Arch Linux Encrypted
linux     /vmlinuz-linux
initrd    /intel-ucode.img
initrd    /initramfs-linux.img

options $X_KERNEL_OPTS
EOF

cat > /boot/loader/loader.conf <<EOF
default   arch
timeout   4
editor    1
EOF

sbctl create-keys
sbctl bundle -s "${X_EFS_PATH:?}"/main.efi

# Remove old entries
efibootmgr | grep 'Arch Linux' | awk '{ print $1 }' | sed -r 's/Boot([^*]{4})\*/\1/' | xargs --no-run-if-empty --max-args 1 efibootmgr --delete-bootnum --bootnum

efibootmgr --create --disk /dev/nvme0n1 --part 1 --label "Arch Linux" --loader 'main.efi' --unicode

# Set root pass
(
set -x
passwd <<<"$(printf '%s\n' "${ROOT_PASS:?}" "$ROOT_PASS")"
)

# Set up user
(
set -x
useradd -m -G wheel,storage,power -g users -s/usr/bin/fish "${USERNAME:?}"
passwd "$USERNAME" <<<"$(printf '%s\n' "${PASSWORD:?}" "$PASSWORD")"
)

# Allow sudo
(
awk -i inplace '{ gsub(/^# %wheel ALL=.*$/, "%wheel ALL=(ALL:ALL) ALL") }; { print }' /etc/sudoers
)
