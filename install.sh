#!/usr/bin/env bash
# Development install: link the widget and the `nightwatch` command into place,
# pointing back at this repo, so edits here are what actually runs. Safe to
# re-run. Anything already in the way that is not a link to this repo is moved
# into $BACKUP - not next to the original, because a copy left in plasmoids/
# would register as a second widget with the same id.
#
# To share the widget instead, build a .plasmoid with ./package.sh.
set -euo pipefail

REPO=$(cd "$(dirname "$0")" && pwd)
ID=com.dakotatalley.nightwatch
PLASMOIDS=$HOME/.local/share/plasma/plasmoids
BIN=$HOME/.local/bin/nightwatch
BACKUP=${XDG_STATE_HOME:-$HOME/.local/state}/nightwatch-install-backup

link() {
  local src=$1 dst=$2
  if [ "$(readlink -f "$dst" 2>/dev/null)" = "$src" ]; then
    echo "  ok      $dst"; return
  fi
  if [ -e "$dst" ] || [ -L "$dst" ]; then
    local bak="$BACKUP/$(basename "$dst").$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$BACKUP"; mv "$dst" "$bak"; echo "  moved   $dst -> $bak"
  fi
  mkdir -p "$(dirname "$dst")"
  ln -s "$src" "$dst"; echo "  linked  $dst -> $src"
}

link "$REPO/plasmoid"                       "$PLASMOIDS/$ID"
link "$REPO/plasmoid/contents/code/nightwatch" "$BIN"

# The widget used the id org.kde.nightwatch before 2.0. Drop that link if it
# still points into this repo; a real directory is left alone.
old=$PLASMOIDS/org.kde.nightwatch
if [ -L "$old" ]; then
  case "$(readlink "$old")" in "$REPO"*|*/nightwatch/plasmoid) rm "$old"; echo "  removed $old (old id)";; esac
fi

echo
echo "QML changes need: systemctl --user restart plasma-plasmashell"
echo "First install only: right-click the panel > Add Widgets > Night Viewing"
