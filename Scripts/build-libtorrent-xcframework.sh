#!/usr/bin/env bash
set -euo pipefail

PACKAGE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK_ROOT="${PACKAGE_ROOT}/.build/libtorrent-xcframework"
ARCHIVE_ROOT="${WORK_ROOT}/archives"
SOURCE_ROOT="${WORK_ROOT}/src"
BUILD_ROOT="${WORK_ROOT}/build"
INSTALL_ROOT="${WORK_ROOT}/install"
BOOST_HEADERS_ROOT="${WORK_ROOT}/boost-headers"
HEADERS_ROOT="${WORK_ROOT}/Headers"
OUTPUT_ROOT="${PACKAGE_ROOT}/Vendor"
OUTPUT_XCFRAMEWORK="${OUTPUT_ROOT}/libtorrent.xcframework"

LIBTORRENT_VERSION="${LIBTORRENT_VERSION:-2.0.12}"
BOOST_VERSION="${BOOST_VERSION:-1.84.0}"
MACOS_ARCHS="${MACOS_ARCHS:-arm64;x86_64}"
MACOS_DEPLOYMENT_TARGET="${MACOS_DEPLOYMENT_TARGET:-14.0}"

LIBTORRENT_URL="${LIBTORRENT_URL:-https://github.com/arvidn/libtorrent/releases/download/v${LIBTORRENT_VERSION}/libtorrent-rasterbar-${LIBTORRENT_VERSION}.tar.gz}"
BOOST_URL="${BOOST_URL:-https://github.com/boostorg/boost/releases/download/boost-${BOOST_VERSION}/boost-${BOOST_VERSION}.tar.gz}"

download_archive() {
  local url="$1"
  local output="$2"

  if [ ! -f "$output" ]; then
    curl -fL "$url" -o "$output"
  fi
}

unpack_archive() {
  local archive="$1"
  local destination="$2"

  rm -rf "$destination"
  mkdir -p "$destination"
  tar -xzf "$archive" -C "$destination" --strip-components 1
}

mkdir -p "$ARCHIVE_ROOT" "$SOURCE_ROOT" "$BUILD_ROOT" "$INSTALL_ROOT" "$OUTPUT_ROOT"

LIBTORRENT_ARCHIVE="${ARCHIVE_ROOT}/libtorrent-rasterbar-${LIBTORRENT_VERSION}.tar.gz"
BOOST_ARCHIVE="${ARCHIVE_ROOT}/boost-dist-${BOOST_VERSION}.tar.gz"
LIBTORRENT_SOURCE="${SOURCE_ROOT}/libtorrent-${LIBTORRENT_VERSION}"
BOOST_SOURCE="${SOURCE_ROOT}/boost-${BOOST_VERSION}"

download_archive "$LIBTORRENT_URL" "$LIBTORRENT_ARCHIVE"
download_archive "$BOOST_URL" "$BOOST_ARCHIVE"
unpack_archive "$LIBTORRENT_ARCHIVE" "$LIBTORRENT_SOURCE"
unpack_archive "$BOOST_ARCHIVE" "$BOOST_SOURCE"

rm -rf "$BOOST_HEADERS_ROOT"
mkdir -p "$BOOST_HEADERS_ROOT"
while IFS= read -r include_dir; do
  rsync -a "${include_dir}/" "$BOOST_HEADERS_ROOT/"
done < <(find "${BOOST_SOURCE}/libs" -type d -name include -print)

rm -rf "${BUILD_ROOT}/macos" "${INSTALL_ROOT}/macos"

cmake -S "$LIBTORRENT_SOURCE" -B "${BUILD_ROOT}/macos" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_CXX_STANDARD=20 \
  -DCMAKE_POLICY_DEFAULT_CMP0144=NEW \
  -DCMAKE_POLICY_DEFAULT_CMP0167=OLD \
  -DCMAKE_POLICY_DEFAULT_CMP0183=OLD \
  -DCMAKE_DISABLE_FIND_PACKAGE_OpenSSL=TRUE \
  -DCMAKE_DISABLE_FIND_PACKAGE_GnuTLS=TRUE \
  -DCMAKE_DISABLE_FIND_PACKAGE_LibGcrypt=TRUE \
  -DCMAKE_OSX_ARCHITECTURES="$MACOS_ARCHS" \
  -DCMAKE_OSX_DEPLOYMENT_TARGET="$MACOS_DEPLOYMENT_TARGET" \
  -DCMAKE_INSTALL_PREFIX="${INSTALL_ROOT}/macos" \
  -DBOOST_ROOT="$BOOST_HEADERS_ROOT" \
  -DBOOST_INCLUDEDIR="$BOOST_HEADERS_ROOT" \
  -DBoost_INCLUDE_DIR="$BOOST_HEADERS_ROOT" \
  -DBoost_NO_SYSTEM_PATHS=ON \
  -DBUILD_SHARED_LIBS=OFF \
  -Dbuild_tests=OFF \
  -Dbuild_examples=OFF \
  -Dbuild_tools=OFF \
  -Dpython-bindings=OFF \
  -Dencryption=OFF

cmake --build "${BUILD_ROOT}/macos" --parallel
cmake --install "${BUILD_ROOT}/macos"

rm -rf "$HEADERS_ROOT" "$OUTPUT_XCFRAMEWORK"
mkdir -p "$HEADERS_ROOT"
rsync -a "${INSTALL_ROOT}/macos/include/libtorrent" "$HEADERS_ROOT/"
rsync -a "${BOOST_HEADERS_ROOT}/boost" "$HEADERS_ROOT/"

cat > "${HEADERS_ROOT}/module.modulemap" <<'MODULEMAP'
module libtorrent [system] {
  umbrella "libtorrent"
  export *
  module * { export * }
}
MODULEMAP

xcodebuild -create-xcframework \
  -library "${INSTALL_ROOT}/macos/lib/libtorrent-rasterbar.a" \
  -headers "$HEADERS_ROOT" \
  -output "$OUTPUT_XCFRAMEWORK"

cat <<EOF
Built:
  $OUTPUT_XCFRAMEWORK

Source archives:
  $LIBTORRENT_URL
  $BOOST_URL
EOF
