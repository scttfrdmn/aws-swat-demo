#!/usr/bin/env bash
# Fetch a small public SWAT+ TxtInOut sample model into data-raw/model/.
#
# SWAT+ ships example datasets with its editor / on the SWAT+ GitHub. The exact
# URL changes across releases, so this script is intentionally explicit: set
# SWAT_SAMPLE_URL to a TxtInOut zip you trust, or drop your own TxtInOut tree
# into data-raw/model/ and skip this.
set -euo pipefail

DEST="$(dirname "$0")/model"
mkdir -p "$DEST"

if [[ -n "${SWAT_SAMPLE_URL:-}" ]]; then
  echo "Downloading sample model from ${SWAT_SAMPLE_URL}…"
  tmp="$(mktemp -d)"
  curl -fsSL "${SWAT_SAMPLE_URL}" -o "${tmp}/model.zip"
  unzip -q "${tmp}/model.zip" -d "$DEST"
  echo "Extracted to ${DEST}"
else
  cat <<'EOF'
No SWAT_SAMPLE_URL set.

Provide a SWAT+ TxtInOut model one of two ways:
  1) export SWAT_SAMPLE_URL=<url-to-a-TxtInOut.zip> and re-run this script, or
  2) copy an existing TxtInOut directory's contents into data-raw/model/.

A TxtInOut directory should contain files like: file.cio, time.sim,
hydrology.hyd, channel*.cha, and (after a run) channel_sd_day.txt.

Sources: the SWAT+ Toolbox / SWAT+ Editor ship example projects; see
https://swatplus.gitbook.io/ and https://github.com/swat-model.
EOF
fi
