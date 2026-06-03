#!/usr/bin/env bash
# Fetch a COMPLETE, runnable SWAT+ TxtInOut model into data-raw/model/.
#
# Default: the official swat-model/SWATPlus-datasets "example1" (the Hubbard
# Brook Watershed model). VERIFIED to run to "Execution successfully completed"
# with the official SWAT+ 61.0.2 ifx Linux binary, producing daily channel
# output (channel_sd_day.txt). The refdata/ models in the swatplus source repo
# are NOT clean standalone models (missing plant.ini entries / *.tes files) and
# segfault — do not use those.
#
# Override with SWAT_SAMPLE_URL to point at a different TxtInOut .zip/.tar.gz.
set -euo pipefail

DEST="$(cd "$(dirname "$0")" && pwd)/model"
mkdir -p "$DEST"
tmp="$(mktemp -d)"

if [[ -n "${SWAT_SAMPLE_URL:-}" ]]; then
  echo "Downloading model from ${SWAT_SAMPLE_URL}…"
  curl -fsSL "${SWAT_SAMPLE_URL}" -o "${tmp}/model.archive"
  case "${SWAT_SAMPLE_URL}" in
    *.tar.gz|*.tgz) tar xzf "${tmp}/model.archive" -C "$DEST" ;;
    *)              unzip -q "${tmp}/model.archive" -d "$DEST" ;;
  esac
else
  echo "Fetching official SWATPlus-datasets example1 (Hubbard Brook)…"
  curl -fsSL https://github.com/swat-model/SWATPlus-datasets/archive/refs/heads/main.tar.gz \
    -o "${tmp}/ds.tgz"
  tar xzf "${tmp}/ds.tgz" -C "${tmp}"
  src="${tmp}/SWATPlus-datasets-main/SWAT+_model_examples/example1"
  if [[ ! -f "${src}/file.cio" ]]; then
    echo "ERROR: expected model not found at ${src}" >&2; exit 1
  fi
  cp "${src}"/* "$DEST"/
fi

rm -rf "$tmp"

# Enable daily channel streamflow output (channel_sd 'daily' column -> y).
if [[ -f "$DEST/print.prt" ]]; then
  awk '$1=="channel_sd"{$2="y"; print; next}{print}' "$DEST/print.prt" > "$DEST/print.prt.new" \
    && mv "$DEST/print.prt.new" "$DEST/print.prt"
fi

echo "Model ready in $DEST ($(ls "$DEST" | wc -l | tr -d ' ') files)."
echo "file.cio present: $([[ -f "$DEST/file.cio" ]] && echo yes || echo NO)"
echo "Run it with the official SWAT+ binary (see docker/Dockerfile); the refdata/"
echo "models in the swatplus SOURCE repo are not runnable standalone."
