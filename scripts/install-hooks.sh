#!/bin/sh
# Configures git to use this repo's tracked hooks. Run once after cloning.
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
git config core.hooksPath "$SCRIPT_DIR/hooks"

echo "Git hooks installed (hooksPath set to $SCRIPT_DIR/hooks)."
