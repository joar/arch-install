#!/bin/bash
set -e

HOST="${1:?"Missing HOST"}"

ssh-copy-id "$HOST"

ssh "$HOST" -- rm -rf '/arch-install'
ssh "$HOST" -- mkdir -p '/arch-install'

scp ./*.sh "$HOST:/arch-install/"

ssh -t "$HOST" -- /bin/bash /arch-install/install-arch.sh
