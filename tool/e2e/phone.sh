#!/usr/bin/env bash
# Drives the phone half of the two-device E2E (see integration_test/e2e_desktop_peer_test.dart).
# Requires one Android device over adb with vBank installed. Coordinates are for a 1080x2340 screen.
#
#   E2E_DIR=/path tool/e2e/phone.sh <command> [args]
#
#   stage                 print the desktop's current stage
#   waitstage NAME        block until the desktop reaches NAME
#   launch | deeplink     start the app / open $E2E_DIR/invite.txt as a vbank:// link
#   passphrase [SHOT]     focus the passphrase field, type it in chunks, reveal, screenshot, tap Join
#   opengroup             back to the list, search $E2E_DIR/name.txt, open the first hit
#   loan [AMOUNT]         from a group's Overview: Loans tab → Request a loan → submit
#   shot NAME [delay]     screenshot to $E2E_DIR/phone/NAME.png
#   tap X Y | type TEXT | back | swipe X1 Y1 X2 Y2
#   log PATTERN [n]       grep the phone's flutter log
set -u
E=${E2E_DIR:-/tmp/vbank-e2e}
mkdir -p "$E/phone"
PASS=${E2E_PASSPHRASE:-e2e-passphrase-2026}
case "${1:-}" in
  stage)     cat "$E/stage" 2>/dev/null; echo ;;
  waitstage) until [ "$(cat "$E/stage" 2>/dev/null)" = "$2" ]; do sleep 3; done; echo "stage=$2" ;;
  launch)    adb shell am start -W -n zm.co.tickethost.vbank/.MainActivity >/dev/null ;;
  deeplink)  LINK=$(cat "$E/invite.txt"); adb shell "am start -W -a android.intent.action.VIEW -d '$LINK' zm.co.tickethost.vbank" | tail -1 ;;
  # The Samsung keyboard drops long input bursts, so type in short chunks.
  passphrase) adb shell input tap 540 924; sleep 1
             for chunk in $(echo "$PASS" | sed 's/\(....\)/\1 /g'); do adb shell input text "$chunk"; sleep 0.6; done
             adb shell input tap 950 924; sleep 1; adb exec-out screencap -p > "$E/phone/${2:-passphrase}.png"
             adb shell input tap 540 1084 ;;
  # Navigate to the run's group from anywhere: back to the list, search by name, open the first hit.
  opengroup) for i in 1 2; do adb shell input keyevent KEYCODE_BACK; sleep 0.7; done
             adb shell am start -W -n zm.co.tickethost.vbank/.MainActivity >/dev/null; sleep 2
             adb shell input tap 540 385; sleep 1
             adb shell input text "$(cat "$E/name.txt" | sed 's/ /%s/g')"; sleep 1.5
             adb shell input keyevent KEYCODE_BACK; sleep 1
             adb shell input tap 540 569; sleep 2 ;;
  # From the group's Overview: scroll the tab row, open Loans, request a 50 loan over the default term.
  loan)      adb shell input swipe 900 370 200 370 300; sleep 1
             adb shell input tap 596 370; sleep 2
             adb shell input tap 540 1520; sleep 2
             adb shell input text "${2:-50}"; sleep 0.5
             adb shell input keyevent KEYCODE_BACK; sleep 1.5
             adb shell input tap 540 1697; sleep 3 ;;
  shot)      sleep "${3:-1.5}"; adb exec-out screencap -p > "$E/phone/$2.png"; echo "$E/phone/$2.png" ;;
  tap)       adb shell input tap "$2" "$3" ;;
  type)      adb shell input text "$(printf '%s' "$2" | sed 's/ /%s/g')" ;;
  back)      adb shell input keyevent KEYCODE_BACK ;;
  swipe)     adb shell input swipe "$2" "$3" "$4" "$5" 300 ;;
  log)       adb logcat -d -s flutter:I 2>/dev/null | grep -iE "$2" | tail -"${3:-15}" ;;
  *)         sed -n 2,16p "$0"; exit 1 ;;
esac
