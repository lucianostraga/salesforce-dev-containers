#!/usr/bin/env bash
# Creates an isolated dev container for a project.
#
# Usage: scripts/new-project.sh <name> <folder>
#   <name>    lowercase letters, numbers and hyphens (e.g. acme)
#   <folder>  the folder that holds the project's repos (e.g. ~/projects/acme), not a repo itself
#
# It copies .devcontainer/ into <folder> and names everything after <name>:
# the container, its home volume (<name>-home) and its Docker network (<name>-net).
set -euo pipefail

usage() { sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'; }

if [ $# -ne 2 ] || [ "$1" = "-h" ] || [ "$1" = "--help" ]; then usage; exit 1; fi

NAME="$1"
FOLDER="$2"
REPO="$(cd "$(dirname "$0")/.." && pwd)"

if [[ ! "$NAME" =~ ^[a-z0-9][a-z0-9-]*$ ]]; then
  echo "ERROR: use lowercase letters, numbers and hyphens for the name (got: $NAME)" >&2; exit 1
fi
mkdir -p "$FOLDER"
FOLDER="$(cd "$FOLDER" && pwd)"
if git -C "$FOLDER" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "ERROR: $FOLDER is inside a git repo. Use the folder that holds the project's repos." >&2; exit 1
fi
if [ -e "$FOLDER/.devcontainer" ]; then
  echo "ERROR: $FOLDER/.devcontainer already exists. Remove or rename it first." >&2; exit 1
fi

cp -R "$REPO/.devcontainer" "$FOLDER/"
perl -pi -e "s/__PROJECT__/$NAME/g" "$FOLDER/.devcontainer/"*
chmod +x "$FOLDER/.devcontainer/init-firewall.sh"

cat <<EOF
Project "$NAME" created in $FOLDER

Next steps:
  1. Add the project's orgs and tools to $FOLDER/.devcontainer/allowed-domains.txt
  2. Open $FOLDER in VS Code and run "Dev Containers: Reopen in Container"
  3. In the terminal: claude, then /login with this project's Claude account
  4. Connect the orgs: sf org login web --alias $NAME-dev
     (Dev Hub: sf org login web --set-default-dev-hub --alias $NAME-devhub)
EOF
