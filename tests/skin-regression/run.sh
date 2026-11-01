#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
work="$(mktemp -d)"
app="$work/SkinRegression.app"
mkdir -p "$app"
python3 - "$root" "$work" <<'PY'
from pathlib import Path
import sys,plistlib
root,work=map(Path,sys.argv[1:])
# Compile the production model; replace only the unrelated launcher utilities.
source=(root/'Natives/SkinModel.m').read_text().replace('#import "utils.h"','#import "TestSupport.h"')
(work/'SkinModel.m').write_text(source)
with (work/'SkinRegression.app/Info.plist').open('wb') as f:
 plistlib.dump(dict(CFBundleIdentifier='org.amethyst.skin-regression',CFBundleExecutable='SkinRegression',CFBundleName='SkinRegression',CFBundlePackageType='APPL',CFBundleVersion='1',CFBundleShortVersionString='1.0',LSRequiresIPhoneOS=True,MinimumOSVersion='17.0'),f)
PY
sdk="$(xcrun --sdk iphonesimulator --show-sdk-path)"
xcrun clang -fobjc-arc -fblocks -arch "$(uname -m)" -mios-simulator-version-min=17.0 -isysroot "$sdk" \
  -framework UIKit -framework Foundation -framework CoreGraphics -framework ImageIO -framework UniformTypeIdentifiers \
  -I "$work" -I "$root/Natives" -I "$root/tests/skin-regression" \
  "$root/tests/skin-regression/main.m" "$work/SkinModel.m" "$root/Natives/SkinPreviewView.m" \
  "$root/Natives/SkinEditorViewController.m" "$root/Natives/SkinManagerViewController.m" -o "$app/SkinRegression"
udid="$(xcrun simctl list devices available -j | python3 -c 'import json,sys; d=json.load(sys.stdin); print(next(x["udid"] for k,v in d["devices"].items() if "iOS" in k for x in v if "iPhone" in x["name"]))')"
xcrun simctl boot "$udid" || true
xcrun simctl bootstatus "$udid" -b
codesign --force --sign - "$app"
xcrun simctl install "$udid" "$app"
xcrun simctl launch "$udid" org.amethyst.skin-regression
container="$(xcrun simctl get_app_container "$udid" org.amethyst.skin-regression data)"
for attempt in $(seq 1 60); do
  if [ -f "$container/Documents/result.txt" ]; then break; fi
  sleep 1
done
cat "$container/Documents/result.txt"
grep -q '^PASS:' "$container/Documents/result.txt"
