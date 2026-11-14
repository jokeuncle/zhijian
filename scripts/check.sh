#!/bin/zsh
set -euo pipefail
TASK_ROOT="${0:A:h:h}"
cd "$TASK_ROOT"
"$TASK_ROOT/scripts/build.sh"
"$TASK_ROOT/.build/release/DictionaryChecks"
python3 "$TASK_ROOT/scripts/verify.py"
codesign --verify --deep --strict "$TASK_ROOT/build/知间.app"
