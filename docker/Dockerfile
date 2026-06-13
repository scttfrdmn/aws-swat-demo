# GAP A — Custom staRburst worker image with the SWAT+ binary baked in.
#
# staRburst has no first-class "add a binary" hook, so the demo supplies its own
# worker base image: the staRburst base (R + future/paws/qs2 + renv) plus the
# official SWAT+ executable and the Python stack used to read NWM Zarr from RODA.
#
# IMPORTANT: we use the OFFICIAL precompiled SWAT+ release binary (built with
# Intel Fortran ifx, statically linked), NOT a from-source gfortran build.
# Verified the hard way: building 61.0.2 from source with gfortran 15 produces a
# binary that spins at 100% CPU / segfaults at simulation entry on real models,
# while the official ifx binary runs them to "Execution successfully completed".
# The official Linux asset is x86_64 only, so this image is linux/amd64.
#
# Build/push with docker/build-and-push.sh, then point staRburst at it as the
# private base image (use_public_base = FALSE).

# x86_64 only: the official SWAT+ Linux binary is ifx/x86_64.
# R_VERSION must match the staRburst client's R so the worker image is used as
# staRburst's base-<R_VERSION> (see docs/DEPLOY-AWS.md, GAP A).
ARG R_VERSION=4.6.0
FROM --platform=linux/amd64 rocker/r-ver:${R_VERSION}

# ---- System deps -------------------------------------------------------------
# Two groups: (1) staRburst's stock base apt set, so this image is a strict
# SUPERSET of starburst-worker:base-<R_VERSION> and staRburst's env layer
# (renv::restore on top) never fails on a missing system lib; (2) Python +
# unzip for the SWAT+ release and the Zarr/RODA reader.
RUN apt-get update && apt-get install -y --no-install-recommends \
      libcurl4-openssl-dev libssl-dev libxml2-dev libpq-dev zlib1g-dev \
      libfontconfig1-dev libfreetype6-dev libharfbuzz-dev libfribidi-dev \
      libgit2-dev libpng-dev libjpeg-dev libtiff-dev git pandoc \
      ca-certificates curl unzip \
      python3 python3-pip python3-venv \
    && rm -rf /var/lib/apt/lists/*

# ---- staRburst worker R deps (mirrors starburst Dockerfile.base) -------------
RUN R -e "install.packages(c('renv','future','globals','listenv','parallelly',\
      'qs2','paws.common','paws.storage','paws.compute','processx','jsonlite',\
      'reticulate'), repos='https://cloud.r-project.org')"

# ---- Python stack for reading NWM retrospective Zarr from RODA ---------------
# --ignore-installed: rocker/r-ver:4.6.0 rides a newer Debian where `packaging`
# is distro-managed (no pip RECORD), so a plain install fails trying to uninstall
# it. We don't need to replace distro packages, just add the Zarr stack on top.
# (This layer is optional for the SWAT+ live run — the worker path is pure R; it
# only matters for the on-worker NWM-RODA read.)
RUN python3 -m pip install --no-cache-dir --break-system-packages --ignore-installed \
      xarray zarr s3fs fsspec numpy pandas

# ---- Official SWAT+ executable (Intel ifx, statically linked) ----------------
# Pinned release. The Linux asset is x86_64; verify the URL/version at
# https://github.com/swat-model/swatplus/releases
ARG SWATPLUS_VERSION=61.0.2
ARG SWATPLUS_ASSET=swatplus-61.0.2-ifx-lin_x86_64-Rel
RUN curl -fsSL -o /tmp/swatplus.zip \
      "https://github.com/swat-model/swatplus/releases/download/${SWATPLUS_VERSION}/${SWATPLUS_ASSET}.zip" \
    && unzip -o /tmp/swatplus.zip -d /tmp/swatplus \
    && install -m 0755 "/tmp/swatplus/${SWATPLUS_ASSET}" /usr/local/bin/swatplus \
    && rm -rf /tmp/swatplus /tmp/swatplus.zip \
    && /usr/local/bin/swatplus --help >/dev/null 2>&1 || true   # smoke-touch
ENV SWAT_BIN=/usr/local/bin/swatplus

WORKDIR /app
# The staRburst worker.R entrypoint is supplied when staRburst builds the
# project image FROM this base; nothing else to add here.
