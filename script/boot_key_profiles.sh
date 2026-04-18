#!/usr/bin/env bash

resolve_scripted_key_profile() {
  local profile_name="${1:-smoke}"

  case "$profile_name" in
    smoke)
      # Let the 3D logo finish its opening animation, press Start (Return → SDL 40)
      # to leave the title, then press A (L-Shift → SDL 225) once the file-select
      # screen is expected to be interactive.
      printf '%s\n' "4500:40:down;4600:40:up;7000:225:down;7100:225:up"
      ;;
    visual)
      # Later timings that keep the app in the foreground long enough for a human to
      # watch title -> file select -> Lakitu intro progression during visual checks.
      printf '%s\n' "9000:40:down;9100:40:up;14000:225:down;14100:225:up"
      ;;
    *)
      echo "Unknown scripted key profile: $profile_name" >&2
      return 1
      ;;
  esac
}
