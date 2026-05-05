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
OPENSSL_HEADERS_ROOT="${WORK_ROOT}/OpenSSLHeaders"
OUTPUT_ROOT="${PACKAGE_ROOT}/Vendor"
OUTPUT_XCFRAMEWORK="${OUTPUT_ROOT}/libtorrent.xcframework"
OPENSSL_XCFRAMEWORK="${OUTPUT_ROOT}/OpenSSL.xcframework"

LIBTORRENT_VERSION="${LIBTORRENT_VERSION:-2.0.12}"
BOOST_VERSION="${BOOST_VERSION:-1.84.0}"
OPENSSL_VERSION="${OPENSSL_VERSION:-3.6.2}"
MACOS_ARCHS="${MACOS_ARCHS:-arm64;x86_64}"
MACOS_DEPLOYMENT_TARGET="${MACOS_DEPLOYMENT_TARGET:-14.0}"

LIBTORRENT_URL="${LIBTORRENT_URL:-https://github.com/arvidn/libtorrent/releases/download/v${LIBTORRENT_VERSION}/libtorrent-rasterbar-${LIBTORRENT_VERSION}.tar.gz}"
BOOST_URL="${BOOST_URL:-https://github.com/boostorg/boost/releases/download/boost-${BOOST_VERSION}/boost-${BOOST_VERSION}.tar.gz}"
OPENSSL_URL="${OPENSSL_URL:-https://github.com/openssl/openssl/releases/download/openssl-${OPENSSL_VERSION}/openssl-${OPENSSL_VERSION}.tar.gz}"

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

openssl_target_for_arch() {
  case "$1" in
    arm64)
      echo "darwin64-arm64-cc"
      ;;
    x86_64)
      echo "darwin64-x86_64-cc"
      ;;
    *)
      echo "Unsupported OpenSSL macOS architecture: $1" >&2
      exit 1
      ;;
  esac
}

build_openssl_slice() {
  local arch="$1"
  local target
  target="$(openssl_target_for_arch "$arch")"

  local source="${BUILD_ROOT}/openssl-${arch}"
  local install="${INSTALL_ROOT}/openssl-${arch}"
  local combined="${BUILD_ROOT}/openssl-combined/${arch}"

  rm -rf "$source" "$install" "$combined"
  mkdir -p "$source" "$combined"
  rsync -a "${OPENSSL_SOURCE}/" "$source/"

  (
    cd "$source"
    CFLAGS="-arch ${arch} -mmacosx-version-min=${MACOS_DEPLOYMENT_TARGET}" \
    LDFLAGS="-arch ${arch} -mmacosx-version-min=${MACOS_DEPLOYMENT_TARGET}" \
      ./Configure "$target" \
        no-shared \
        no-tests \
        no-apps \
        no-docs \
        "--prefix=${install}" \
        "--openssldir=${install}/ssl"
    make -j"$(sysctl -n hw.logicalcpu)"
    make install_sw
  )

  libtool -static -o "${combined}/libopenssl.a" \
    "${install}/lib/libssl.a" \
    "${install}/lib/libcrypto.a"
}

mkdir -p "$ARCHIVE_ROOT" "$SOURCE_ROOT" "$BUILD_ROOT" "$INSTALL_ROOT" "$OUTPUT_ROOT"

LIBTORRENT_ARCHIVE="${ARCHIVE_ROOT}/libtorrent-rasterbar-${LIBTORRENT_VERSION}.tar.gz"
BOOST_ARCHIVE="${ARCHIVE_ROOT}/boost-dist-${BOOST_VERSION}.tar.gz"
OPENSSL_ARCHIVE="${ARCHIVE_ROOT}/openssl-${OPENSSL_VERSION}.tar.gz"
LIBTORRENT_SOURCE="${SOURCE_ROOT}/libtorrent-${LIBTORRENT_VERSION}"
BOOST_SOURCE="${SOURCE_ROOT}/boost-${BOOST_VERSION}"
OPENSSL_SOURCE="${SOURCE_ROOT}/openssl-${OPENSSL_VERSION}"

download_archive "$LIBTORRENT_URL" "$LIBTORRENT_ARCHIVE"
download_archive "$BOOST_URL" "$BOOST_ARCHIVE"
download_archive "$OPENSSL_URL" "$OPENSSL_ARCHIVE"
unpack_archive "$LIBTORRENT_ARCHIVE" "$LIBTORRENT_SOURCE"
unpack_archive "$BOOST_ARCHIVE" "$BOOST_SOURCE"
unpack_archive "$OPENSSL_ARCHIVE" "$OPENSSL_SOURCE"

rm -rf "$BOOST_HEADERS_ROOT"
mkdir -p "$BOOST_HEADERS_ROOT"
while IFS= read -r include_dir; do
  rsync -a "${include_dir}/" "$BOOST_HEADERS_ROOT/"
done < <(find "${BOOST_SOURCE}/libs" -type d -name include -print)

rm -rf "${BUILD_ROOT}/macos" "${INSTALL_ROOT}/macos" "${INSTALL_ROOT}/openssl-universal" "$OPENSSL_HEADERS_ROOT" "$OPENSSL_XCFRAMEWORK"

IFS=';' read -r -a ARCHS <<< "$MACOS_ARCHS"
for arch in "${ARCHS[@]}"; do
  build_openssl_slice "$arch"
done

OPENSSL_UNIVERSAL_ROOT="${INSTALL_ROOT}/openssl-universal"
mkdir -p "${OPENSSL_UNIVERSAL_ROOT}/lib" "${OPENSSL_UNIVERSAL_ROOT}/include" "$OPENSSL_HEADERS_ROOT"

LIBSSL_SLICES=()
LIBCRYPTO_SLICES=()
LIBOPENSSL_SLICES=()
for arch in "${ARCHS[@]}"; do
  LIBSSL_SLICES+=("${INSTALL_ROOT}/openssl-${arch}/lib/libssl.a")
  LIBCRYPTO_SLICES+=("${INSTALL_ROOT}/openssl-${arch}/lib/libcrypto.a")
  LIBOPENSSL_SLICES+=("${BUILD_ROOT}/openssl-combined/${arch}/libopenssl.a")
done

lipo -create "${LIBSSL_SLICES[@]}" -output "${OPENSSL_UNIVERSAL_ROOT}/lib/libssl.a"
lipo -create "${LIBCRYPTO_SLICES[@]}" -output "${OPENSSL_UNIVERSAL_ROOT}/lib/libcrypto.a"
lipo -create "${LIBOPENSSL_SLICES[@]}" -output "${OPENSSL_UNIVERSAL_ROOT}/lib/libopenssl.a"

rsync -a "${INSTALL_ROOT}/openssl-${ARCHS[0]}/include/openssl" "${OPENSSL_UNIVERSAL_ROOT}/include/"
rsync -a "${OPENSSL_UNIVERSAL_ROOT}/include/openssl" "$OPENSSL_HEADERS_ROOT/"

xcodebuild -create-xcframework \
  -library "${OPENSSL_UNIVERSAL_ROOT}/lib/libopenssl.a" \
  -headers "$OPENSSL_HEADERS_ROOT" \
  -output "$OPENSSL_XCFRAMEWORK"

cmake -S "$LIBTORRENT_SOURCE" -B "${BUILD_ROOT}/macos" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_CXX_STANDARD=20 \
  -DCMAKE_POLICY_DEFAULT_CMP0144=NEW \
  -DCMAKE_POLICY_DEFAULT_CMP0167=OLD \
  -DCMAKE_POLICY_DEFAULT_CMP0183=OLD \
  -DCMAKE_OSX_ARCHITECTURES="$MACOS_ARCHS" \
  -DCMAKE_OSX_DEPLOYMENT_TARGET="$MACOS_DEPLOYMENT_TARGET" \
  -DCMAKE_INSTALL_PREFIX="${INSTALL_ROOT}/macos" \
  -DOPENSSL_ROOT_DIR="$OPENSSL_UNIVERSAL_ROOT" \
  -DOPENSSL_INCLUDE_DIR="${OPENSSL_UNIVERSAL_ROOT}/include" \
  -DOPENSSL_SSL_LIBRARY="${OPENSSL_UNIVERSAL_ROOT}/lib/libssl.a" \
  -DOPENSSL_CRYPTO_LIBRARY="${OPENSSL_UNIVERSAL_ROOT}/lib/libcrypto.a" \
  -DOPENSSL_USE_STATIC_LIBS=TRUE \
  -DBOOST_ROOT="$BOOST_HEADERS_ROOT" \
  -DBOOST_INCLUDEDIR="$BOOST_HEADERS_ROOT" \
  -DBoost_INCLUDE_DIR="$BOOST_HEADERS_ROOT" \
  -DBoost_NO_SYSTEM_PATHS=ON \
  -DBUILD_SHARED_LIBS=OFF \
  -Dbuild_tests=OFF \
  -Dbuild_examples=OFF \
  -Dbuild_tools=OFF \
  -Dpython-bindings=OFF \
  -Dencryption=ON

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
  $OPENSSL_XCFRAMEWORK
  $OUTPUT_XCFRAMEWORK

Source archives:
  $LIBTORRENT_URL
  $BOOST_URL
  $OPENSSL_URL
EOF
