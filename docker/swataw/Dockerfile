# Headless SWAT+ AW (Automatic Workflow) image — builds SWAT+ models without a GUI.
FROM qgis/qgis:3.40-jammy

ENV DEBIAN_FRONTEND=noninteractive
ENV HOME=/root
ENV swatplus_wf_dir=/root/.SWAT/SWATPlus/Workflow
ENV QT_QPA_PLATFORM=offscreen

RUN apt-get update && apt-get install -y --no-install-recommends \
      wget unzip ca-certificates cython3 python3-pip python3-dev build-essential cmake xvfb mpich libmpich-dev libgdal-dev \
    && rm -rf /var/lib/apt/lists/*

# Base is jammy: Python 3.10 + NumPy 1.21 — QSWAT+'s native era, which avoids the
# NumPy-2 incompatibilities (removed np.int_t, dtype-size mismatches, stricter
# array reductions) that QGIS 3.44/NumPy 2 triggered. Install pandas/geopandas via
# APT so they match the system NumPy 1.21 (pip pulls NumPy 2 -> binary mismatch).
# peewee (pure-python) is needed by the SWAT+ Editor and isn't packaged.
RUN apt-get update && apt-get install -y --no-install-recommends \
      python3-pandas python3-geopandas \
    && rm -rf /var/lib/apt/lists/* \
    && pip3 install --no-cache-dir peewee

WORKDIR /tmp/awinstall
RUN wget -q -O aw.tar.gz "https://github.com/celray/swatplus-automatic-workflow/archive/refs/heads/master.tar.gz" \
 && wget -q -O TauDEM5Bin_Linux.zip "https://github.com/celray/swatplus-automatic-workflow/releases/download/v1.0.4/TauDEM5Bin_Linux.zip" \
 && mkdir -p /root/.SWAT/SWATPlus /root/.local/share/swatplus \
 && tar xzf aw.tar.gz \
 && unzip -q TauDEM5Bin_Linux.zip \
 && mv swatplus-automatic-workflow-master /root/.SWAT/SWATPlus/Workflow \
 && mv TauDEM5Bin /root/.local/share/swatplus/TauDEM5Bin \
 && mkdir -p /usr/local/share/SWATPlus \
 && cp -r /root/.local/share/swatplus/TauDEM5Bin /usr/local/share/SWATPlus/TauDEM5Bin \
 && chmod -R 777 /root/.local/share/swatplus/TauDEM5Bin /usr/local/share/SWATPlus/TauDEM5Bin \
 && chmod +x /root/.SWAT/SWATPlus/Workflow/swatplus_aw.sh \
 && rm -rf /tmp/awinstall

# Pre-compile the QSWAT+ Cython extensions to .so with correct numpy/python
# includes, so pyximport/import loads prebuilt modules rather than compiling
# (and failing to find numpy headers) at runtime. (np.int_t exists in NumPy 1.21,
# so no source patch is needed on the jammy base.)
COPY swatplus_wgn.sqlite /root/.SWAT/SWATPlus/Workflow/editor_api/swatplus_wgn.sqlite
COPY build_pyx.py /tmp/build_pyx.py
RUN python3 /tmp/build_pyx.py

ENV PATH=$PATH:/root/.SWAT/SWATPlus/Workflow
WORKDIR /model

# TauDEM from source (CMake): bundled v1.0.4 bins link libgdal.so.26 (GDAL 3.2),
# but this image has GDAL 3.10 (.so.36); they fail to load. v5.5.0 also fixes the
# OGR NULL-layer-name bug that broke channel streamnet on modern GDAL. The script
# builds, OVERWRITES the bundled bins, and asserts streamnet no longer needs .so.26.
COPY build_taudem.sh /tmp/build_taudem.sh
RUN bash /tmp/build_taudem.sh
