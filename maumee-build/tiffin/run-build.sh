#!/bin/bash
WF=$swatplus_wf_dir
cd /model
export PYTHONPATH=/model:$PYTHONPATH
export BASE_DIR=/model
run_stage () {
  echo "=== STAGE: $1 ==="
  python3 "$WF/main_stages/$1" /model 2>&1 | tail -12
  echo "--- $1 rc=${PIPESTATUS[0]} ---"
}
run_stage prepare_project.py
run_stage run_qswat.py
run_stage run_editor.py
echo "=== RESULT ==="
find /model -type d -name "TxtInOut" 2>/dev/null
find /model -name "channel_sd_day.txt" 2>/dev/null | head
