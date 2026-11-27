#!/usr/bin/env bash
# Build the MCP components for one MySQL release inside an oraclelinux:9 container:
# component_mcp_guard (and the test-only component_mcp_session_probe) for MySQL 8.4, 9.7 and
# 26.x, and with BUILD_ENDPOINT=ON component_mcp (MySQL 26.10+), which is built inside the
# server tree because it links MySQL Router's HTTP libraries.
#
# Usage: [BUILD_ENDPOINT=ON] [DOCKER_PLATFORM=linux/arm64] \
#          scripts/build-components-docker.sh <mysql-tag> [out-dir]
#   e.g. scripts/build-components-docker.sh mysql-8.4.11 dist/mcp-8.4.11
#        BUILD_ENDPOINT=ON scripts/build-components-docker.sh mysql-26.10.0 dist/mcp-26.10.0
# Output in out-dir: component_mcp_guard.so, mcp_guard.json, component_mcp_session_probe.so,
# and component_mcp.so and mcp.json with BUILD_ENDPOINT=ON. The MySQL source tree is kept in
# mysql-server-<tag>/ for reuse (configured per architecture in bld-<arch>/).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MYSQL_TAG="${1:?mysql tag, e.g. mysql-8.4.11}"
OUTPUT_DIR="${2:-dist/mcp-${MYSQL_TAG#mysql-}}"
case "$(printf '%s' "${BUILD_ENDPOINT:-OFF}" | tr '[:lower:]' '[:upper:]')" in
  1 | ON | YES | TRUE | Y) BUILD_ENDPOINT=ON ;;
  *) BUILD_ENDPOINT=OFF ;;
esac

echo "==> Building the MCP components for $MYSQL_TAG (component_mcp: $BUILD_ENDPOINT)"

docker run --rm \
  ${DOCKER_PLATFORM:+--platform "$DOCKER_PLATFORM"} \
  -v "$REPO_ROOT:/workspace:rw" -w /workspace \
  -e MYSQL_TAG="$MYSQL_TAG" -e OUTPUT_DIR="$OUTPUT_DIR" -e BUILD_ENDPOINT="$BUILD_ENDPOINT" \
  -e HOST_UID="$(id -u)" -e HOST_GID="$(id -g)" \
  oraclelinux:9 bash -c '
    set -euo pipefail
    ARCH=$(uname -m)
    TS=/opt/rh/gcc-toolset-14/root/usr/bin

    echo "==> Installing build dependencies..."
    dnf install -y oraclelinux-developer-release-el9 dnf-plugins-core >/dev/null 2>&1
    dnf config-manager --enable ol9_codeready_builder >/dev/null 2>&1
    dnf install -y --nodocs \
      gcc gcc-c++ cmake make git bison pkg-config rpcgen \
      libtirpc-devel openldap-devel cyrus-sasl-devel \
      libcurl-devel protobuf-devel protobuf-compiler \
      zlib-devel openssl-devel ncurses-devel \
      gcc-toolset-14-gcc gcc-toolset-14-gcc-c++ gcc-toolset-14-binutils \
      gcc-toolset-14-annobin-annocheck gcc-toolset-14-annobin-plugin-gcc \
      >/dev/null 2>&1

    MYSQL_SRC="/workspace/mysql-server-${MYSQL_TAG}"
    # The tree is owned by the host user: without this git refuses it ("dubious ownership"),
    # the tag check fails, and every run re-clones.
    git config --global --add safe.directory "$MYSQL_SRC"
    CURRENT_TAG="$(git -C "$MYSQL_SRC" describe --tags --exact-match 2>/dev/null || true)"
    if [ "$CURRENT_TAG" != "$MYSQL_TAG" ] || \
       [ ! -f "$MYSQL_SRC/include/mysql/components/component_implementation.h" ]; then
      echo "==> Cloning MySQL source ($MYSQL_TAG)..."
      rm -rf "$MYSQL_SRC"
      git clone -q --depth 1 --branch "$MYSQL_TAG" https://github.com/mysql/mysql-server.git "$MYSQL_SRC"
    fi
    # Per architecture: a multi-arch build in the same checkout must not reuse the other
    # architecture'"'"'s CMake cache and generated headers.
    MYSQL_BLD="${MYSQL_SRC}/bld-${ARCH}"
    mkdir -p "$MYSQL_BLD"
    # .configure-ok is written only after cmake succeeds, so a failed configure is redone.
    if [ ! -f "$MYSQL_BLD/.configure-ok" ]; then
      echo "==> Configuring MySQL (generated headers)..."
      VER="${MYSQL_TAG#mysql-}"
      cmake -S "$MYSQL_SRC" -B "$MYSQL_BLD" \
        -DCMAKE_C_COMPILER=$TS/gcc -DCMAKE_CXX_COMPILER=$TS/g++ \
        -DDOWNLOAD_BOOST=1 -DWITH_BOOST="/tmp/boost_mysql_${VER}" \
        -DWITH_UNIT_TESTS=OFF -DWITH_ROUTER=OFF -DWITH_RAPID=OFF -DWITH_NDB=OFF \
        -DWITH_NDBCLUSTER=OFF -DWITH_GROUP_REPLICATION=OFF -DWITH_AUTHENTICATION_WEBAUTHN=OFF \
        -DWITH_EXAMPLE_STORAGE_ENGINE=OFF -DCMAKE_BUILD_TYPE=Release >/dev/null
      touch "$MYSQL_BLD/.configure-ok"
    fi

    echo "==> Building component_mcp_guard..."
    BUILD="/workspace/build-${ARCH}-${MYSQL_TAG}"
    rm -rf "$BUILD"
    cmake -S /workspace -B "$BUILD" \
      -DCMAKE_C_COMPILER=$TS/gcc -DCMAKE_CXX_COMPILER=$TS/g++ -DCMAKE_BUILD_TYPE=Release \
      -DMYSQL_SOURCE_DIR="$MYSQL_SRC" -DMYSQL_BUILD_DIR="$MYSQL_BLD" >/dev/null
    cmake --build "$BUILD" -j"$(nproc)"

    OUT="/workspace/$OUTPUT_DIR"
    mkdir -p "$OUT"
    rm -f "$OUT/component_mcp.so" "$OUT/mcp.json"
    cp "$BUILD/component_mcp_guard.so" "$BUILD/component_mcp_session_probe.so" \
       /workspace/src/mcp/guard/mcp_guard.json "$OUT/"

    if [ "$BUILD_ENDPOINT" = ON ]; then
      echo "==> Building component_mcp in the server tree..."
      rm -rf "$MYSQL_SRC/components/mcp"
      cp -r /workspace/src/mcp/endpoint "$MYSQL_SRC/components/mcp"
      cmake -S "$MYSQL_SRC" -B "$MYSQL_BLD" >/dev/null  # components are globbed
      cmake --build "$MYSQL_BLD" --target component_mcp -j"$(nproc)"
      cp "$MYSQL_BLD/plugin_output_directory/component_mcp.so" /workspace/src/mcp/endpoint/mcp.json "$OUT/"
    fi
    ls -la "$OUT"
    chown -R "${HOST_UID}:${HOST_GID}" "$MYSQL_SRC" "$BUILD" "$OUT" 2>/dev/null || true
  '
