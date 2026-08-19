#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/config/build.env"

fail() {
	printf 'test-termux-auth-prefix: %s\n' "$*" >&2
	exit 1
}

PATCH_FILE="$ROOT_DIR/patches/coomi-prefix.patch"
[[ -f "$PATCH_FILE" ]] || fail "patch not found: $PATCH_FILE"
grep -Fq 'packages/termux-auth/build.sh' "$PATCH_FILE" || \
	fail 'coomi-prefix.patch does not patch termux-auth build.sh'
grep -Fq 'coomi_termux_auth_header' "$PATCH_FILE" || \
	fail 'patch does not define the termux-auth header rewrite hook'
grep -Fq 'sed -i "s#/data/data/com.termux#${TERMUX_APP__DATA_DIR}#g"' "$PATCH_FILE" || \
	fail 'patch does not rewrite the legacy termux-auth header path'

TEST_ROOT="$(mktemp -d)"
trap 'rm -rf -- "$TEST_ROOT"' EXIT
mkdir -p "$TEST_ROOT/packages/termux-auth"
git -C "$TEST_ROOT" init -q
cat > "$TEST_ROOT/packages/termux-auth/build.sh" <<'EOF'
TERMUX_PKG_HOMEPAGE=https://github.com/termux/termux-auth
TERMUX_PKG_DESCRIPTION="Password authentication library and utility for Termux"
TERMUX_PKG_LICENSE="GPL-3.0"
TERMUX_PKG_MAINTAINER="@termux"
TERMUX_PKG_VERSION=1.5.0
TERMUX_PKG_REVISION=1
TERMUX_PKG_SRCURL=https://github.com/termux/termux-auth/archive/refs/tags/v${TERMUX_PKG_VERSION}.tar.gz
TERMUX_PKG_SHA256=bfe928b1c40822ad12d5673f37e464af237d74aef08c6b1187c5d8b96b848d52
TERMUX_PKG_AUTO_UPDATE=false
TERMUX_PKG_DEPENDS="openssl"
TERMUX_PKG_BREAKS="termux-auth-dev"
TERMUX_PKG_REPLACES="termux-auth-dev"

termux_step_pre_configure() {
	CPPFLAGS+=" -DTERMUX_HOME=\\\"${TERMUX_ANDROID_HOME}\\\" -DTERMUX_PREFIX=\\\"${TERMUX_PREFIX}\\\""
}
EOF

git -C "$TEST_ROOT" apply --check --unidiff-zero --include='packages/termux-auth/build.sh' "$PATCH_FILE" || \
	fail 'termux-auth patch does not apply to the pinned upstream shape'
git -C "$TEST_ROOT" apply --unidiff-zero --include='packages/termux-auth/build.sh' "$PATCH_FILE"

massagedir="$TEST_ROOT/massage"
header="$massagedir$COOMI_PREFIX/include/termux-auth.h"
mkdir -p "$(dirname -- "$header")"
cat > "$header" <<'EOF'
# ifndef TERMUX_HOME
#  define TERMUX_HOME "/data/data/com.termux/files/home"
# endif
# ifndef TERMUX_PREFIX
#  define TERMUX_PREFIX "/data/data/com.termux/files/usr"
# endif
# define AUTH_HASH_FILE_PATH TERMUX_HOME "/.termux_authinfo"
EOF

TERMUX_PKG_MASSAGEDIR="$massagedir" \
TERMUX_PREFIX="$COOMI_PREFIX" \
TERMUX_APP__DATA_DIR="$COOMI_DATA_DIR" \
TERMUX_ANDROID_HOME="$COOMI_DATA_DIR/files/home" \
bash -c 'source "$1"; termux_step_post_massage' _ "$TEST_ROOT/packages/termux-auth/build.sh"

if grep -Fq '/data/data/com.termux' "$header"; then
	fail 'termux-auth header still contains the legacy Termux path'
fi
grep -Fq "\"$COOMI_DATA_DIR/files/home\"" "$header" || \
	fail 'termux-auth header did not use the Coomi home path'
grep -Fq "\"$COOMI_PREFIX\"" "$header" || \
	fail 'termux-auth header did not use the Coomi prefix'

printf 'termux-auth Coomi prefix regression: PASS\n'
