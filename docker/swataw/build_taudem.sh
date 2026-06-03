#!/bin/bash
set -euo pipefail
cd /tmp
wget -q -O taudem.tar.gz "https://github.com/dtarb/TauDEM/archive/refs/tags/v5.5.0.tar.gz"
tar xzf taudem.tar.gz
cd TauDEM-5.5.0/src
# mpich wrapper flags carry -flto=auto which this gcc rejects; drop them (mpic++ adds what is needed)
sed -i "s/\${MPI_COMPILE_FLAGS}//g; s/\${MPI_LINK_FLAGS}//g" CMakeLists.txt
mkdir -p build && cd build
cmake .. -DCMAKE_BUILD_TYPE=Release -DCMAKE_CXX_FLAGS="-fno-lto"
make -j4
DEST=/usr/local/share/SWATPlus/TauDEM5Bin
mkdir -p "$DEST"
# overwrite any bundled (old-GDAL) binaries with the freshly built ones
find . -maxdepth 1 -type f -executable -exec cp -f {} "$DEST/" \;
ln -sf "$DEST/moveoutletstostrm" "$DEST/moveoutletstostreams" || true
chmod -R 777 "$DEST"
# verify: streamnet must NOT link libgdal.so.26
if ldd "$DEST/streamnet" | grep -q "libgdal.so.26"; then
  echo "FATAL: streamnet still links libgdal.so.26"; exit 1
fi
echo "TauDEM v5.5.0 installed; streamnet links: $(ldd "$DEST/streamnet" | grep -o "libgdal.so.[0-9]*")"
rm -rf /tmp/TauDEM-5.5.0 /tmp/taudem.tar.gz
