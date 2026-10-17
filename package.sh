#!/usr/bin/env bash
# Build dist/nightwatch-<version>.plasmoid, the file people install with
#   Add Widgets > Get New > Install Widget From Local File
# or
#   kpackagetool6 -t Plasma/Applet -i nightwatch-<version>.plasmoid
# A .plasmoid is just a zip of the package directory's contents.
set -euo pipefail

REPO=$(cd "$(dirname "$0")" && pwd)
version=$(python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1]))["KPlugin"]["Version"])' \
          "$REPO/plasmoid/metadata.json")
out=$REPO/dist/nightwatch-$version.plasmoid

mkdir -p "$REPO/dist"
rm -f "$out"
# python's zipfile rather than `zip`, which is often not installed; it also
# records unix permissions so the script keeps its executable bit
# The repo-root LICENSE goes in too: MIT requires the notice to travel with
# every copy, and the .plasmoid is the copy people actually get.
python3 -I - "$REPO/plasmoid" "$out" "$REPO/LICENSE" <<'EOF'
import os, sys, zipfile
src, out, lic = sys.argv[1], sys.argv[2], sys.argv[3]
with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
    for d, _, files in sorted(os.walk(src)):
        for f in sorted(files):
            p = os.path.join(d, f)
            z.write(p, os.path.relpath(p, src))
    z.write(lic, "LICENSE")
EOF
echo "$out"
