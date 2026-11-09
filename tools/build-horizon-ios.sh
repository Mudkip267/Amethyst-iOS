#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
source_dir="$(cd "${1:?Horizon source checkout required}" && pwd)"
output_dir="${2:?Output directory required}"
expected_commit=cf2707b035917d9f93fb7ea89ddc077396e19e96
target=aarch64-apple-ios

cd "$source_dir"
test "$(git rev-parse HEAD)" = "$expected_commit"
bash tools/ci/ios-toolchain.sh
git apply --check "$repo_root/patches/horizon-ios-embed.patch"
git apply "$repo_root/patches/horizon-ios-embed.patch"

export IPHONEOS_DEPLOYMENT_TARGET=16.0
export HORIZON_TELEMETRY_URL=off
export HORIZON_MSA_CLIENT_ID=331e08f8-172d-43b9-835a-3108c2fcdbf3
export CARGO_PROFILE_RELEASE_CODEGEN_UNITS=16
export CARGO_PROFILE_RELEASE_LTO=false
export CARGO_INCREMENTAL=0

cargo rustc --locked --release --target "$target" -p horizon-client --lib \
    --no-default-features --features audio,horizon-extras,amethyst-embedded \
    --crate-type cdylib -- -C link-arg=-Wl,-headerpad_max_install_names

mkdir -p "$output_dir/HorizonNotices"
engine="$output_dir/libAmethystHorizon.dylib"
cp "target/$target/release/libhorizon_client.dylib" "$engine"
install_name_tool -id @rpath/libAmethystHorizon.dylib "$engine"
symbols="$(nm -gU "$engine")"
grep -q ' _amethyst_horizon_main$' <<< "$symbols"
xcrun vtool -show-build "$engine"

(cd packaging/ios && xcodegen generate)
xcodebuild -project packaging/ios/HorizonIOS.xcodeproj -target HorizonLauncherKit \
    -configuration Release -sdk iphoneos -arch arm64 CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= DEBUG_INFORMATION_FORMAT=dwarf \
    CONFIGURATION_BUILD_DIR="$output_dir" build

test -s "$output_dir/HorizonLauncherKit.framework/HorizonLauncherKit"
cp LICENSE THIRD_PARTY_NOTICES.md "$output_dir/HorizonNotices/"
printf '%s\n' "$expected_commit" > "$output_dir/HorizonNotices/engine-source-commit.txt"
