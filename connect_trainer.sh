#!/bin/zsh
set -euo pipefail

usage() {
  cat <<'USAGE'
Connect a previously paired Bluetooth Smart bicycle trainer to a MacBook Pro.

Usage:
  ./connect_trainer.sh --address <MAC>
  ./connect_trainer.sh --name "<Trainer Name>"

  -a, --address   Bluetooth MAC address of the trainer (preferred, no spaces).
  -n, --name      Trainer name as shown in Bluetooth preferences (case-insensitive).
  -h, --help      Show this message.

Requires the `blueutil` CLI (brew install blueutil).
USAGE
  exit 1
}

command -v blueutil >/dev/null 2>&1 || {
  echo "blueutil is required. Install it with: brew install blueutil" >&2
  exit 1
}

TRAINER_NAME=""
TRAINER_ADDRESS=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    -a|--address)
      [[ $# -lt 2 ]] && usage
      TRAINER_ADDRESS="$2"
      shift 2
      ;;
    -n|--name)
      [[ $# -lt 2 ]] && usage
      TRAINER_NAME="$2"
      shift 2
      ;;
    -h|--help)
      usage
      ;;
    *)
      if [[ -z "$TRAINER_NAME" && -z "$TRAINER_ADDRESS" ]]; then
        TRAINER_NAME="$1"
        shift
      else
        echo "Unknown argument: $1" >&2
        usage
      fi
      ;;
  esac
done

[[ -z "$TRAINER_NAME" && -z "$TRAINER_ADDRESS" ]] && usage

ensure_bluetooth_on() {
  local current_state
  current_state="$(blueutil --power || echo 0)"
  if [[ "$current_state" != "1" ]]; then
    echo "Enabling Bluetooth..."
    blueutil --power 1
    sleep 2
  fi
}

is_connected() {
  local status
  if ! status="$(blueutil --is-connected "$1" 2>/dev/null)"; then
    echo 0
    return
  fi
  echo "$status"
}

resolve_address_from_name() {
  local target="$1"
  blueutil --paired | awk -v name="$target" '
    /^address:/ { addr=$2; next }
    /^[[:space:]]+/ {
      entry=$0
      sub(/^[[:space:]]+/, "", entry)
      sub(/ \(.*/, "", entry)
      if (tolower(entry) == tolower(name)) {
        print addr
        exit
      }
    }
  '
}

ensure_bluetooth_on

if [[ -z "$TRAINER_ADDRESS" ]]; then
  TRAINER_ADDRESS="$(resolve_address_from_name "$TRAINER_NAME")"
  if [[ -z "$TRAINER_ADDRESS" ]]; then
    echo "Could not find trainer named '$TRAINER_NAME' in the paired device list." >&2
    echo "Pair the trainer via System Settings ▸ Bluetooth, or supply --address." >&2
    exit 2
  fi
fi

echo "Using trainer address: $TRAINER_ADDRESS"

if [[ "$(is_connected "$TRAINER_ADDRESS")" == "1" ]]; then
  echo "Trainer already connected."
  exit 0
fi

attempt=0
max_attempts=5
while (( attempt < max_attempts )); do
  echo "Connecting (attempt $((attempt + 1))/$max_attempts)..."
  if blueutil --connect "$TRAINER_ADDRESS"; then
    sleep 2
    if [[ "$(is_connected "$TRAINER_ADDRESS")" == "1" ]]; then
      echo "Trainer connected."
      exit 0
    fi
  fi
  attempt=$((attempt + 1))
  sleep 3
fi

echo "Failed to connect to trainer at $TRAINER_ADDRESS." >&2
exit 3
