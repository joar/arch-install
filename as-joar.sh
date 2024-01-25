set -x
set -o errexit pipefail

cd ~ || exit 1
# Install pikaur
mkdir -p git
cd git || exit 1
git clone https://aur.archlinux.org/pikaur.git
cd pikaur || exit 1
makepkg -fsri --noconfirm
