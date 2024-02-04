#!/bin/bash

set -x
set -e

# BEGIN desktop
sudo pacman --noconfirm -S gnome gnome-extra gdm
sudo systemctl enable gdm.service


gsettings set org.gnome.desktop.interface show-battery-percentage true
gsettings set org.gnome.desktop.interface color-scheme "'prefer-dark'"
gsettings set org.gnome.desktop.interface enable-animations false
gsettings set org.gnome.desktop.interface enable-hot-corners false
gsettings set org.gnome.desktop.sound event-sounds false
gsettings set org.gnome.settings-daemon.plugins.power idle-dim false
gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-ac-type "'nothing'"
# END desktop

# BEGIN applications
pikaur --noconfirm --noedit -S \
  zoom \
  slack-desktop \
  firefox
# END applications

# BEGIN ibus_and_input
sudo pacman -S ibus
cat > /etc/environment <<EOF
GTK_IM_MODULE=ibus
QT_IM_MODULE=ibus
XMODIFIERS=@im=ibus
EOF

sudo cp xkb-symbols-se /usr/share/X11/xkb/symbols/se

gsettings set org.gnome.desktop.input-sources sources "[('xkb', 'se+dvorak_a5')]"
gsettings set org.gnome.desktop.input-sources xkb-options "['lv3:ralt_switch', 'compose:rctrl', 'ctrl:nocaps', 'caps:none']"
gsettings set org.freedesktop.ibus.panel.emoji hotkey "['<Super>period', '<Super>semicolon']"
gsettings set org.gnome.desktop.interface gtk-enable-primary-paste false
gsettings set org.gnome.desktop.peripherals.keyboard delay 'uint32 250'
# END ibus_and_input


# BEGIN snapper
sudo pacman -S snapper snap-pac
sudo snapper -c root create-config /
snapper -c root create-config /
# END snapper

