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
FROM --platform=linux/amd64 rocker/r-ver:4.4.2

# ---- System deps: Python (Zarr/RODA) + unzip for the SWAT+ release ----------
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl unzip \
      python3 python3-pip python3-venv \
      libcurl4-openssl-dev libssl-dev libxml2-dev \
    && rm -rf /var/lib/apt/lists/*

# ---- staRburst worker R deps (mirrors starburst Dockerfile.base) -------------
RUN R -e "install.packages(c('renv','future','globals','listenv','parallelly',\
      'qs2','paws.common','paws.storage','paws.compute','processx','jsonlite',\
      'reticulate'), repos='https://cloud.r-project.org')"

# ---- Python stack for reading NWM retrospective Zarr from RODA ---------------
RUN python3 -m pip install --no-cache-dir --break-system-packages \
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
