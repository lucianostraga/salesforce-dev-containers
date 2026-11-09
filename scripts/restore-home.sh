#!/usr/bin/env bash
# Restores a project's home volume (<name>-home) from a .tgz made with backup-home.sh.
#
# Usage: scripts/restore-home.sh <name> <file.tgz>
# Then open the project folder in VS Code and run "Dev Containers: Reopen in Container".
set -euo pipefail

if [ $# -ne 2 ] || [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
  sed -n '2,5p' "$0" | sed 's/^# \{0,1\}//'; exit 1
fi

NAME="$1"
FILE="$(cd "$(dirname "$2")" && pwd)/$(basename "$2")"
[ -f "$FILE" ] || { echo "ERROR: $FILE not found" >&2; exit 1; }

if docker volume inspect "$NAME-home" >/dev/null 2>&1; then
  read -r -p "Volume $NAME-home already exists. Overwrite matching files? (y/N) " answer
  [ "$answer" = "y" ] || exit 1
else
  docker volume create "$NAME-home" >/dev/null
fi

docker run --rm -v "$NAME-home":/data -v "$(dirname "$FILE")":/backup alpine \
  tar xzf "/backup/$(basename "$FILE")" -C /data

echo "Restored $NAME-home from $FILE"
