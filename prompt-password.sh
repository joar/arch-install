#!/bin/bash
PROMPT="${1:?"Missing PROMPT"}"

declare -a entries

function prompt() {
  if test -n "$1"; then
    dialog --msgbox "$1" 0 0
  fi
  if ! dialog_result="$(dialog \
    --stdout \
    --insecure \
    --clear --passwordform "$PROMPT" 0 0 0 \
    "Enter" 1 1 "" 1 9 40 0 \
    "Confirm" 2 1 "" 2 9 40 0
    )"; then
    echo "Prompt \"$PROMPT\" aborted"
    exit 2
  fi

  IFS=$'\n' read -r -d '' -a entries <<<"$dialog_result"
}

prompt

until test -n "${entries[0]}" && test "${entries[0]}" = "${entries[1]}"; do
  if ! test "${#entries[@]}" -lt 3; then
    prompt "Expected length of 2, got $(declare -p entries)";
  fi

  if ! test "${entries[0]}" = "${entries[1]}"; then
    prompt "Passwords do not match";
  fi

  if test -z "${entries[0]}"; then
    prompt "Password is empty"
  fi
done
echo "${entries[0]}"
