#!/bin/sh
# Builds libtailscale static archives and dynamic libraries for iOS.
#
# Why dylib? Go does not support `-buildmode=c-shared` for ios/arm64, so we
# build the official c-archive and link it into a dynamic library with the
# Apple toolchain. This is intended for non-App-Store/enterprise/simulator
# use; App Store apps should use the official static framework approach.
set -eu

cd "$(dirname "$0")/.."
ROOT="$PWD"

# Build the official-style Go static archives first.
make libtailscale_ios.a
make libtailscale_ios_sim_arm64.a
make libtailscale_ios_sim_x86_64.a
make libtailscale_ios_sim.a

DEV_SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
SIM_SDK="$(xcrun --sdk iphonesimulator --show-sdk-path)"
MIN_IOS="${MIN_IOS:-12.0}"

mkdir -p dist/ios dist/ios-sim dist/macos

# --- Device (arm64) dylib ------------------------------------------------
xcrun clang \
  -arch arm64 \
  -isysroot "$DEV_SDK" \
  -mios-version-min="$MIN_IOS" \
  -dynamiclib \
  -install_name @rpath/libtailscale.dylib \
  -Wl,-all_load \
  -framework CoreFoundation \
  -framework Security \
  -o dist/ios/libtailscale.dylib \
  "$ROOT/tailscale.c" \
  "$ROOT/libtailscale_ios.a"

# --- Simulator dylibs (arm64 + x86_64, then lipo together) ---------------
xcrun clang \
  -arch arm64 \
  -isysroot "$SIM_SDK" \
  -mios-simulator-version-min="$MIN_IOS" \
  -dynamiclib \
  -install_name @rpath/libtailscale.dylib \
  -Wl,-all_load \
  -framework CoreFoundation \
  -framework Security \
  -o dist/ios-sim/libtailscale_arm64.dylib \
  "$ROOT/tailscale.c" \
  "$ROOT/libtailscale_ios_sim_arm64.a"

xcrun clang \
  -arch x86_64 \
  -isysroot "$SIM_SDK" \
  -mios-simulator-version-min="$MIN_IOS" \
  -dynamiclib \
  -install_name @rpath/libtailscale.dylib \
  -Wl,-all_load \
  -framework CoreFoundation \
  -framework Security \
  -o dist/ios-sim/libtailscale_x86_64.dylib \
  "$ROOT/tailscale.c" \
  "$ROOT/libtailscale_ios_sim_x86_64.a"

lipo -create \
  dist/ios-sim/libtailscale_arm64.dylib \
  dist/ios-sim/libtailscale_x86_64.dylib \
  -output dist/ios-sim/libtailscale.dylib

rm -f dist/ios-sim/libtailscale_arm64.dylib dist/ios-sim/libtailscale_x86_64.dylib

# --- macOS dylib (also built from the static archive + C wrapper) ---------
make libtailscale.a
MAC_SDK="$(xcrun --sdk macosx --show-sdk-path)"
xcrun clang   -arch "$(uname -m)"   -isysroot "$MAC_SDK"   -mmacosx-version-min=15.0   -dynamiclib   -install_name @rpath/libtailscale.dylib   -Wl,-all_load   -framework CoreFoundation   -framework Security   -o dist/macos/libtailscale.dylib   "$ROOT/tailscale.c"   "$ROOT/libtailscale.a"

# --- Headers, C wrapper source, and static archives alongside the dylibs ---
cp tailscale.h dist/ios/tailscale.h
cp tailscale.c dist/ios/tailscale.c
cp libtailscale.h dist/ios/libtailscale.h 2>/dev/null || true
cp libtailscale_ios.a dist/ios/libtailscale_ios.a
cp tailscale.h dist/ios-sim/tailscale.h
cp tailscale.c dist/ios-sim/tailscale.c
cp libtailscale.h dist/ios-sim/libtailscale.h 2>/dev/null || true
cp libtailscale_ios_sim.a dist/ios-sim/libtailscale_ios_sim.a 2>/dev/null || true
cp tailscale.h dist/macos/tailscale.h
cp tailscale.c dist/macos/tailscale.c
cp libtailscale.h dist/macos/libtailscale.h 2>/dev/null || true

echo
echo "Built iOS/macOS dylibs under dist/:"
find dist -maxdepth 2 -type f | sort
