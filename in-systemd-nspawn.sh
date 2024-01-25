set -x
set -e

sudo -u joar bash /arch-install/as-joar.sh

# Install plymouth-git
pikaur -Sy plymouth-git --noconfirm --noedit


plymouth-set-default-theme -R spinner
sbctl generate-bundles -s
bootctl install
mkinitcpio -P
bootctl update
