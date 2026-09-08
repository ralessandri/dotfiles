#!/bin/bash

APP_ID="$1"
shift
LAUNCH_CMD=( "$@" )

# Holt alle IDs dieser App als Array
MAP=( $(niri msg --json windows | jq -r --arg app_id "$APP_ID" '.[] | select(.app_id == $app_id) | .id') )

if [ ${#MAP[@]} -eq 0 ]; then
    # App läuft nicht -> starten
    "${LAUNCH_CMD[@]}" &
elif [ ${#MAP[@]} -eq 1 ]; then
    # Nur ein Fenster -> beim erneuten Drücken zur vorherigen App zurück
    ACTIVE_ID=$(niri msg --json windows | jq -r '.[] | select(.is_focused == true) | .id')
    if [[ "${MAP[0]}" == "${ACTIVE_ID}" ]]; then
        niri msg action focus-window-previous
    else
        niri msg action focus-window --id "${MAP[0]}"
    fi
else
    # Holt die ID des aktuell fokussierten Fensters
    ACTIVE_ID=$(niri msg --json windows | jq -r '.[] | select(.is_focused == true) | .id')

    # Sucht die Position des aktiven Fensters im Array
    NEXT_ID=${MAP[0]}
    for i in "${!MAP[@]}"; do
       if [[ "${MAP[$i]}" == "${ACTIVE_ID}" ]]; then
           # Nimm das nächste Element, oder fange von vorne an
           NEXT_INDEX=$(( (i + 1) % ${#MAP[@]} ))
           NEXT_ID=${MAP[$NEXT_INDEX]}
           break
       fi
    done
    niri msg action focus-window --id "$NEXT_ID"
fi
