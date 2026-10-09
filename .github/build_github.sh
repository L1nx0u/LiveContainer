#!/bin/sh
# Builds LiveContainer.ipa and LiveContainer+SideStore.ipa from an xcarchive.
# Required env: scheme, archive_path. Runs on macos-latest.
set -eu
if [ -n "${BASH_VERSION:-}" ]; then set -o pipefail; fi

: "${scheme:?scheme env var is required}"
: "${archive_path:?archive_path env var is required}"

# PlistBuddy Add is not idempotent: ignore "already exists" so re-runs work.
plist_add() {
  /usr/libexec/PlistBuddy -c "$1" "$2" 2>/dev/null || true
}

# Portable in-place sed (macOS BSD sed needs -i '', GNU sed does not).
portable_sed() {
  if sed --version >/dev/null 2>&1; then
    sed -i "$@"
  else
    sed -i '' "$@"
  fi
}

# --- fetch dylibify (only needed for the +SideStore variant) ---
# LIEF-based exe->dylib converter, replaces dead dylibify binary.
if [ ! -x ./dylibify ]; then
  if ! python3 -c "import lief" 2>/dev/null; then
    python3 -m pip install --user lief || pip3 install --user lief || /usr/bin/pip3 install --user lief
  fi
  python3 -c "import lief" || { echo "error: lief install failed" >&2; exit 1; }
  printf '#!/bin/sh\nexec python3 .github/exe2dylib.py "$1" "$2" SideStore\n' > ./dylibify
  chmod +x ./dylibify
fi

if ! command -v ldid >/dev/null 2>&1; then
  brew install ldid
fi

# --- move lc to working folder ---
if [ ! -d "$archive_path.xcarchive/Products/Applications" ]; then
  echo "error: archive not found at $archive_path.xcarchive/Products/Applications" >&2
  exit 1
fi
rm -rf Payload tmp
mv "$archive_path.xcarchive/Products/Applications" Payload

# temporarily move sidestore support framework to tmp before zip
mkdir -p tmp
mv Payload/LiveContainer.app/Frameworks/SideStoreSupport.framework ./tmp

zip -r "$scheme.ipa" "Payload" -x "._*" -x ".DS_Store" -x "__MACOSX"

mv ./tmp/SideStoreSupport.framework Payload/LiveContainer.app/Frameworks

# put sidestore related keys into Info.plist and settings bundle
plist_add 'Add :ALTAppGroups array' ./Payload/LiveContainer.app/Info.plist
plist_add 'Add :ALTAppGroups: string group.com.SideStore.SideStore' ./Payload/LiveContainer.app/Info.plist

plist_add "Add :CFBundleURLTypes:1 dict" ./Payload/LiveContainer.app/Info.plist
plist_add "Add :CFBundleURLTypes:1:CFBundleURLName string com.kdt.livecontainer.sidestoreurlscheme" ./Payload/LiveContainer.app/Info.plist
plist_add "Add :CFBundleURLTypes:1:CFBundleURLSchemes array" ./Payload/LiveContainer.app/Info.plist
plist_add "Add :CFBundleURLTypes:1:CFBundleURLSchemes:0 string sidestore" ./Payload/LiveContainer.app/Info.plist
plist_add "Add :CFBundleURLTypes:2 dict" ./Payload/LiveContainer.app/Info.plist
plist_add "Add :CFBundleURLTypes:2:CFBundleURLName string com.kdt.livecontainer.sidestorebackupurlscheme" ./Payload/LiveContainer.app/Info.plist
plist_add "Add :CFBundleURLTypes:2:CFBundleURLSchemes array" ./Payload/LiveContainer.app/Info.plist
plist_add "Add :CFBundleURLTypes:2:CFBundleURLSchemes:0 string sidestore-com.kdt.livecontainer" ./Payload/LiveContainer.app/Info.plist

plist_add "Add :INIntentsSupported array" ./Payload/LiveContainer.app/Info.plist
plist_add "Add :INIntentsSupported:0 string RefreshAllIntent" ./Payload/LiveContainer.app/Info.plist
plist_add "Add :INIntentsSupported:1 string ViewAppIntent" ./Payload/LiveContainer.app/Info.plist
plist_add "Add :NSUserActivityTypes array" ./Payload/LiveContainer.app/Info.plist
plist_add "Add :NSUserActivityTypes:0 string RefreshAllIntent" ./Payload/LiveContainer.app/Info.plist
plist_add "Add :NSUserActivityTypes:1 string ViewAppIntent" ./Payload/LiveContainer.app/Info.plist

plist_add "Add :PreferenceSpecifiers:3:Type string PSToggleSwitchSpecifier" ./Payload/LiveContainer.app/Settings.bundle/Root.plist
plist_add "Add :PreferenceSpecifiers:3:Title string Open SideStore" ./Payload/LiveContainer.app/Settings.bundle/Root.plist
plist_add "Add :PreferenceSpecifiers:3:Key string LCOpenSideStore" ./Payload/LiveContainer.app/Settings.bundle/Root.plist
plist_add "Add :PreferenceSpecifiers:3:DefaultValue bool false" ./Payload/LiveContainer.app/Settings.bundle/Root.plist

# download SideStore (floating nightly: log fingerprint for reproducibility)
cd tmp
rm -f SideStore.ipa
curl -fSL --retry 3 -o SideStore.ipa https://github.com/L1nx0u/SideStore/releases/download/nightly/SideStore.ipa
if command -v shasum >/dev/null 2>&1; then
  shasum -a 256 SideStore.ipa
fi
unzip -o -q SideStore.ipa
cd ..

if [ ! -d ./tmp/Payload/SideStore.app ]; then
  echo "error: SideStore.app missing after unzip" >&2
  exit 1
fi

# SideStore
mv ./tmp/Payload/SideStore.app ./Payload/LiveContainer.app/Frameworks/SideStoreApp.framework
./dylibify ./Payload/LiveContainer.app/Frameworks/SideStoreApp.framework/SideStore ./Payload/LiveContainer.app/Frameworks/SideStoreApp.framework/SideStore.dylib
rm ./Payload/LiveContainer.app/Frameworks/SideStoreApp.framework/SideStore
mv ./Payload/LiveContainer.app/Frameworks/SideStoreApp.framework/SideStore.dylib ./Payload/LiveContainer.app/Frameworks/SideStoreApp.framework/SideStore
ldid -S"" ./Payload/LiveContainer.app/Frameworks/SideStoreApp.framework/SideStore
cp ./.github/sidelc/LCAppInfo.plist ./Payload/LiveContainer.app/Frameworks/SideStoreApp.framework/

# copy intents
cp ./Payload/LiveContainer.app/Frameworks/SideStoreApp.framework/Intents.intentdefinition ./Payload/LiveContainer.app/
cp ./Payload/LiveContainer.app/Frameworks/SideStoreApp.framework/ViewApp.intentdefinition ./Payload/LiveContainer.app/
rm -rf ./Payload/LiveContainer.app/Metadata.appintents
cp -r ./Payload/LiveContainer.app/Frameworks/SideStoreApp.framework/Metadata.appintents ./Payload/LiveContainer.app/Metadata.appintents
portable_sed 's/9SideStore20RefreshAllAppsIntentV/16SideStoreSupport20RefreshAllAppsIntentV/g' ./Payload/LiveContainer.app/Metadata.appintents/extract.actionsdata
portable_sed 's/9SideStore26RefreshAllAppsWidgetIntentV/16SideStoreSupport26RefreshAllAppsWidgetIntentV/g' ./Payload/LiveContainer.app/Metadata.appintents/extract.actionsdata

# the Shortcuts metadata must reference our module now; fail loudly if
# SideStore renamed the intents instead of shipping a broken widget
for intent in 16SideStoreSupport20RefreshAllAppsIntentV 16SideStoreSupport26RefreshAllAppsWidgetIntentV; do
  if ! grep -q "$intent" ./Payload/LiveContainer.app/Metadata.appintents/extract.actionsdata; then
    echo "error: $intent missing from extract.actionsdata; SideStore intent names changed" >&2
    exit 1
  fi
done

# AltWidgetExtension (fail loudly if SideStore renames it)
if [ ! -d ./Payload/LiveContainer.app/Frameworks/SideStoreApp.framework/PlugIns/AltWidgetExtension.appex ]; then
  echo "error: AltWidgetExtension.appex missing; SideStore layout changed. PlugIns contains:" >&2
  ls ./Payload/LiveContainer.app/Frameworks/SideStoreApp.framework/PlugIns >&2 || true
  exit 1
fi
mv ./Payload/LiveContainer.app/Frameworks/SideStoreApp.framework/PlugIns/AltWidgetExtension.appex ./Payload/LiveContainer.app/PlugIns/LiveWidgetExtension.appex
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier com.kdt.livecontainer.LiveWidget"  ./Payload/LiveContainer.app/PlugIns/LiveWidgetExtension.appex/Info.plist
/usr/libexec/PlistBuddy -c "Set :CFBundleExecutable LiveWidgetExtension"  ./Payload/LiveContainer.app/PlugIns/LiveWidgetExtension.appex/Info.plist
mv ./Payload/LiveContainer.app/PlugIns/LiveWidgetExtension.appex/AltWidgetExtension ./Payload/LiveContainer.app/PlugIns/LiveWidgetExtension.appex/LiveWidgetExtension

# Sign
rm -rf .zsign_cache
find Payload -type d -name "_CodeSignature" -exec rm -rf {} +

ldid -S.github/sidelc/LiveWidgetExtension_adhoc.xml ./Payload/LiveContainer.app/PlugIns/LiveWidgetExtension.appex/LiveWidgetExtension

# package
zip -r "$scheme+SideStore.ipa" "Payload" -x "._*" -x ".DS_Store" -x "__MACOSX"
