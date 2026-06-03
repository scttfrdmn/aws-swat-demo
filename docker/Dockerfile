# GAP A — Custom staRburst worker image with the SWAT+ binary baked in.
#
# staRburst has no first-class "add a binary" hook, so the demo supplies its own
# worker base image: the staRburst base (R + future/paws/qs2 + renv) plus a
# compiled SWAT+ executable and the Python stack used to read NWM Zarr from RODA.
#
# Build/push with docker/build-and-push.sh, then point staRburst at it as the
# private base image (use_public_base = FALSE).
#
# NOTE: pin SWATPLUS_VERSION to a release you trust before any real run.

ARG BASE_IMAGE=rocker/r-ver:4.4.2
FROM ${BASE_IMAGE}

# ---- System deps: R build libs + Fortran (SWAT+) + Python (Zarr/RODA) --------
RUN apt-get update && apt-get install -y --no-install-recommends \
      build-essential gfortran cmake git \
      libcurl4-openssl-dev libssl-dev libxml2-dev \
      python3 python3-pip python3-venv \
      ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# ---- staRburst worker R deps (mirrors starburst Dockerfile.base) -------------
RUN R -e "install.packages(c('renv','future','globals','listenv','parallelly',\
      'qs2','paws.common','paws.storage','paws.compute','processx','jsonlite',\
      'reticulate'), repos='https://cloud.r-project.org')"

# ---- Python stack for reading NWM retrospective Zarr from RODA ---------------
RUN python3 -m pip install --no-cache-dir --break-system-packages \
      xarray zarr s3fs fsspec numpy

# ---- SWAT+ executable --------------------------------------------------------
# SWAT+ is open source (https://swat.tamu.edu/, github.com/swat-model). Build
# from a pinned release. Adjust the source/URL to the version you validated.
ARG SWATPLUS_VERSION=main
RUN git clone --depth 1 --branch ${SWATPLUS_VERSION} \
      https://github.com/swat-model/swatplus.git /opt/swatplus-src \
    && cd /opt/swatplus-src \
    && (cmake -S . -B build && cmake --build build --config Release \
         || (echo "NOTE: adjust this build to the SWAT+ source layout" && false)) \
    && install -m 0755 build/swatplus /usr/local/bin/swatplus
ENV SWAT_BIN=/usr/local/bin/swatplus

WORKDIR /app
# The staRburst worker.R entrypoint is supplied when staRburst builds the
# project image FROM this base; nothing else to add here.
