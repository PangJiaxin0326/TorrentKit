#!/usr/bin/env bash
set -euo pipefail

PACKAGE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK_ROOT="${PACKAGE_ROOT}/.build/torrentkit-libtorrent"
SOURCE_ROOT="${WORK_ROOT}/src"
BUILD_ROOT="${WORK_ROOT}/build"
INSTALL_ROOT="${WORK_ROOT}/install"

LIBTORRENT_URL="${LIBTORRENT_URL:-https://github.com/arvidn/libtorrent.git}"
LIBTORRENT_REF="${LIBTORRENT_REF:-RC_2_0}"
BOOST_URL="${BOOST_URL:-https://github.com/boostorg/boost.git}"
BOOST_REF="${BOOST_REF:-boost-1.84.0}"

mkdir -p "${SOURCE_ROOT}" "${BUILD_ROOT}" "${INSTALL_ROOT}"

if [ ! -d "${SOURCE_ROOT}/boost/.git" ]; then
  git clone --depth 1 --recurse-submodules --shallow-submodules \
    --branch "${BOOST_REF}" \
    "${BOOST_URL}" \
    "${SOURCE_ROOT}/boost"
else
  git -C "${SOURCE_ROOT}/boost" fetch --depth 1 origin "${BOOST_REF}"
  git -C "${SOURCE_ROOT}/boost" checkout FETCH_HEAD
  git -C "${SOURCE_ROOT}/boost" submodule update --init --recursive --depth 1
fi

if [ ! -d "${SOURCE_ROOT}/libtorrent/.git" ]; then
  git clone --depth 1 --recurse-submodules --shallow-submodules \
    --branch "${LIBTORRENT_REF}" \
    "${LIBTORRENT_URL}" \
    "${SOURCE_ROOT}/libtorrent"
else
  git -C "${SOURCE_ROOT}/libtorrent" fetch --depth 1 origin "${LIBTORRENT_REF}"
  git -C "${SOURCE_ROOT}/libtorrent" checkout FETCH_HEAD
  git -C "${SOURCE_ROOT}/libtorrent" submodule update --init --recursive --depth 1
fi

cmake -S "${SOURCE_ROOT}/libtorrent" -B "${BUILD_ROOT}/libtorrent" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_CXX_STANDARD=20 \
  -DCMAKE_INSTALL_PREFIX="${INSTALL_ROOT}" \
  -DBOOST_ROOT="${SOURCE_ROOT}/boost" \
  -DBoost_NO_SYSTEM_PATHS=ON \
  -DBUILD_SHARED_LIBS=ON \
  -Dbuild_tests=OFF \
  -Dbuild_examples=OFF \
  -Dbuild_tools=OFF \
  -Dpython-bindings=OFF \
  -Dencryption=OFF

cmake --build "${BUILD_ROOT}/libtorrent" --parallel
cmake --install "${BUILD_ROOT}/libtorrent"

cat <<EOF
libtorrent is installed for TorrentKit at:
  ${INSTALL_ROOT}

Build the package with:
  swift build --package-path "${PACKAGE_ROOT}"
EOF
