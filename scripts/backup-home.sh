#!/usr/bin/env bash
# Saves a project's home volume (<name>-home) to a .tgz file: Claude login, memory, history, MCP servers,
# Salesforce orgs and Dev Hub. Use it to move a project to another machine, or as a backup.
#
# Usage: scripts/backup-home.sh <name> [destination-folder]
# The file contains access tokens: encrypt it before moving it.
set -euo pipefail

if [ $# -lt 1 ] || [ $# -gt 2 ] || [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
  sed -n '2,6p' "$0" | sed 's/^# \{0,1\}//'; exit 1
fi

NAME="$1"
DEST="$(cd "${2:-.}" && pwd)"
FILE="$NAME-home-$(date +%F).tgz"

if ! docker volume inspect "$NAME-home" >/dev/null 2>&1; then
  echo "ERROR: volume $NAME-home not found (see: docker volume ls)" >&2; exit 1
fi

docker run --rm -v "$NAME-home":/data -v "$DEST":/backup alpine tar czf "/backup/$FILE" -C /data .
chmod 600 "$DEST/$FILE"

echo "Saved $DEST/$FILE"
echo "It contains access tokens: encrypt it before moving it."
