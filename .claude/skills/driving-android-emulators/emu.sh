# Remote keys, screenshots and the outside IP for the Shikoo emulators.
#   source .claude/skills/driving-android-emulators/emu.sh                    # TV, emulator-5556
#   D=emulator-5554 source .claude/skills/driving-android-emulators/emu.sh    # phone
source /d/dev/android-toolchain/env.sh >/dev/null 2>&1
D=${D:-emulator-5556}; A="adb -s $D"; SHOTS=${SHOTS:-/d/dev/shikoo-spike/shots}

boot(){ $A wait-for-device; until [ "$($A shell getprop sys.boot_completed | tr -d '\r')" = 1 ]; do sleep 3; done; echo booted; }
k(){ for x in "$@"; do $A shell input keyevent "KEYCODE_$x"; sleep 0.8; done; }
shot(){ sleep "${2:-1}"; $A exec-out screencap -p > "$SHOTS/$1.png"; echo "$SHOTS/$1.png"; }
# rm first: a failed dump leaves the previous screen's file behind, which then reports a stale focus
focus(){ $A shell 'rm -f /sdcard/u.xml; uiautomator dump /sdcard/u.xml >/dev/null 2>&1; cat /sdcard/u.xml 2>/dev/null' | tr '>' '\n' | grep 'focused="true"' | grep -oE '(text|content-desc|resource-id)="[^"]+"' | tail -3; }
# The outside IP as Cloudflare sees it. Plain HTTP to a fixed Cloudflare IP: the device has no curl.
ip_out(){ $A shell '(printf "GET /cdn-cgi/trace HTTP/1.1\r\nHost: cloudflare.com\r\nConnection: close\r\n\r\n"; sleep 6) | toybox nc -w 8 104.16.133.229 80' | grep -E '^(ip|loc)=' | tr '\n' ' '; echo; }
