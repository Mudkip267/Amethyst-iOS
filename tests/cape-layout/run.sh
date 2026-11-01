#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
work="$(mktemp -d)"
app="$work/CapeLayout.app"
mkdir -p "$app"
python3 - "$root" "$work" <<'PY'
from pathlib import Path
import sys,plistlib
root,work=map(Path,sys.argv[1:])
source=(root/'Natives/SkinEditorViewController.m').read_text()
start=source.index('@interface SkinCapeCard :')
end=source.index('@interface SkinEditorViewController ()',start)
(work/'CapeCardUnderTest.h').write_text(source[start:end])
with (work/'CapeLayout.app/Info.plist').open('wb') as f:
 plistlib.dump(dict(CFBundleIdentifier='org.amethyst.cape-layout-test',CFBundleExecutable='CapeLayout',CFBundleName='CapeLayout',CFBundlePackageType='APPL',CFBundleVersion='1',CFBundleShortVersionString='1.0',LSRequiresIPhoneOS=True,MinimumOSVersion='17.0'),f)
PY
sdk="$(xcrun --sdk iphonesimulator --show-sdk-path)"
xcrun clang -fobjc-arc -fblocks -arch "$(uname -m)" -mios-simulator-version-min=17.0 -isysroot "$sdk" -framework UIKit -framework Foundation -framework CoreGraphics -I "$work" "$root/tests/cape-layout/main.m" -o "$app/CapeLayout"
udid="$(xcrun simctl list devices available -j | python3 -c 'import json,sys; d=json.load(sys.stdin); print(next(x["udid"] for k,v in d["devices"].items() if "iOS" in k for x in v if "iPhone" in x["name"]))')"
xcrun simctl boot "$udid" || true
xcrun simctl bootstatus "$udid" -b
codesign --force --sign - "$app"
xcrun simctl install "$udid" "$app"
xcrun simctl launch "$udid" org.amethyst.cape-layout-test
container="$(xcrun simctl get_app_container "$udid" org.amethyst.cape-layout-test data)"
for attempt in $(seq 1 30); do
    if [ -f "$container/Documents/result.txt" ]; then break; fi
    sleep 1
done
cat "$container/Documents/result.txt"
grep -q '^PASS:' "$container/Documents/result.txt"
