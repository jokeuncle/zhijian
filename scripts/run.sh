#!/bin/zsh
set -euo pipefail
TASK_ROOT="${0:A:h:h}"
if [[ ! -d "$TASK_ROOT/build/知间.app" ]]; then "$TASK_ROOT/scripts/build.sh"; fi
open "$TASK_ROOT/build/知间.app"
