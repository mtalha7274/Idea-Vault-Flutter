#!/bin/sh
# Flutter embeds native-asset frameworks (for example objective_c.framework,
# used by path_provider) without a dSYM, so App Store uploads warn
# "Upload Symbols Failed". Create a dSYM for any embedded framework that
# has none, so its UUID is known and crashes in it can be symbolicated.

if [ "$DEBUG_INFORMATION_FORMAT" != "dwarf-with-dsym" ]; then
  exit 0
fi

frameworks_dir="${TARGET_BUILD_DIR}/${FRAMEWORKS_FOLDER_PATH}"
[ -d "$frameworks_dir" ] || exit 0
mkdir -p "$DWARF_DSYM_FOLDER_PATH"

for framework in "$frameworks_dir"/*.framework; do
  [ -d "$framework" ] || continue
  name=$(basename "$framework" .framework)
  binary="$framework/$name"
  dsym="$DWARF_DSYM_FOLDER_PATH/$name.framework.dSYM"
  [ -f "$binary" ] || continue
  [ -d "$dsym" ] && continue
  echo "Generating dSYM for $name.framework"
  xcrun dsymutil "$binary" -o "$dsym" 2>/dev/null || true
done
