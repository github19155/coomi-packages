#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/config/build.env"

fail() {
	printf 'prepare-termux-packages: %s\n' "$*" >&2
	exit 1
}

if [[ $# -ne 1 ]]; then
	fail "usage: $0 <empty-destination>"
fi

TERMUX_DIR="$1"
PATCH_FILE="$ROOT_DIR/patches/coomi-prefix.patch"
TERMUX_EXEC_PATCH_FILE="$ROOT_DIR/patches/termux-exec-coomi.patch"
TERMUX_TOOLS_PATCH_FILE="$ROOT_DIR/patches/termux-tools-coomi.patch"

[[ -f "$PATCH_FILE" ]] || fail "patch not found: $PATCH_FILE"
[[ -f "$TERMUX_EXEC_PATCH_FILE" ]] || fail "patch not found: $TERMUX_EXEC_PATCH_FILE"
[[ -f "$TERMUX_TOOLS_PATCH_FILE" ]] || fail "patch not found: $TERMUX_TOOLS_PATCH_FILE"

if [[ -e "$TERMUX_DIR" && ! -d "$TERMUX_DIR" ]]; then
	fail "destination exists and is not a directory: $TERMUX_DIR"
fi

mkdir -p "$TERMUX_DIR"
if find "$TERMUX_DIR" -mindepth 1 -print -quit | grep -q .; then
	fail "destination must be empty: $TERMUX_DIR"
fi
TERMUX_DIR="$(cd -- "$TERMUX_DIR" && pwd)"

(
	cd "$TERMUX_DIR"
	git init -q
	git remote add origin "$TERMUX_PACKAGES_REPOSITORY"
	git fetch --depth 1 origin "$TERMUX_PACKAGES_COMMIT"
	git checkout --detach FETCH_HEAD

	[[ "$(git rev-parse HEAD)" == "$TERMUX_PACKAGES_COMMIT" ]] || {
		printf 'unexpected upstream commit: %s\n' "$(git rev-parse HEAD)" >&2
		exit 1
	}

	git apply --check "$PATCH_FILE"
	git apply "$PATCH_FILE"
	git apply --check "$TERMUX_EXEC_PATCH_FILE"
	git apply "$TERMUX_EXEC_PATCH_FILE"
	git apply --check "$TERMUX_TOOLS_PATCH_FILE"
	git apply "$TERMUX_TOOLS_PATCH_FILE"
)

PROPERTIES_FILE="$TERMUX_DIR/scripts/properties.sh"
[[ -f "$PROPERTIES_FILE" ]] || fail "upstream properties file missing"

required_lines=(
	'TERMUX_APP__PACKAGE_NAME="com.coomi.android"'
	'TERMUX_REPO_APP__PACKAGE_NAME="com.coomi.android"'
	'TERMUX_REPO_APP__DATA_DIR="/data/data/com.coomi.android"'
	'TERMUX_REPO__PREFIX="/data/data/com.coomi.android/files/usr"'
	'CGCT_DEFAULT_PREFIX="/data/data/com.coomi.android/files/usr/glibc"'
	'export CGCT_DIR="/data/data/com.coomi.android/cgct"'
)

for line in "${required_lines[@]}"; do
	grep -Fqx -- "$line" "$PROPERTIES_FILE" || fail "missing patched line: $line"
done

START_BUILD_FILE="$TERMUX_DIR/scripts/build/termux_step_start_build.sh"
if ! grep -Fqx $'\tTERMUX_PKG_FULLVERSION+="+coomi1"' "$START_BUILD_FILE"; then
	fail "missing Coomi version suffix in $START_BUILD_FILE"
fi

TERMUX_EXEC_BUILD_FILE="$TERMUX_DIR/packages/termux-exec/build.sh"
[[ -f "$TERMUX_EXEC_BUILD_FILE" ]] || fail "upstream termux-exec build definition missing"
grep -Fq 'coomi_termux_exec_file' "$TERMUX_EXEC_BUILD_FILE" || \
	fail "missing Coomi termux-exec cleanup hook in $TERMUX_EXEC_BUILD_FILE"
grep -Fq 'find "$TERMUX_PKG_MASSAGEDIR" -type f -print0' "$TERMUX_EXEC_BUILD_FILE" || \
	fail "missing full termux-exec path scan in $TERMUX_EXEC_BUILD_FILE"
grep -Fq 'grep -Iq .' "$TERMUX_EXEC_BUILD_FILE" || \
	fail "missing text-file guard in $TERMUX_EXEC_BUILD_FILE"
grep -Fq 'sed -i "s#/data/data/com.termux#${TERMUX_APP__DATA_DIR}#g"' "$TERMUX_EXEC_BUILD_FILE" || \
	fail "missing legacy path replacement in $TERMUX_EXEC_BUILD_FILE"

TERMUX_TOOLS_BUILD_FILE="$TERMUX_DIR/packages/termux-tools/build.sh"
[[ -f "$TERMUX_TOOLS_BUILD_FILE" ]] || fail "upstream termux-tools build definition missing"
grep -Fq 'coomi_termux_tools_rewrite_paths' "$TERMUX_TOOLS_BUILD_FILE" || \
	fail "missing Coomi termux-tools cleanup hook in $TERMUX_TOOLS_BUILD_FILE"
grep -Fq 'sed -i "s#/data/data/com.termux#${TERMUX_APP__DATA_DIR}#g"' "$TERMUX_TOOLS_BUILD_FILE" || \
	fail "missing legacy path replacement in $TERMUX_TOOLS_BUILD_FILE"

(
	cd "$TERMUX_DIR"
	TERMUX_PKGS__BUILD__REPO_ROOT_DIR="$TERMUX_DIR" \
	COOMI_EXPECTED_APP_PACKAGE="$COOMI_APP_PACKAGE" \
	COOMI_EXPECTED_DATA_DIR="$COOMI_DATA_DIR" \
	COOMI_EXPECTED_PREFIX="$COOMI_PREFIX" \
	bash -c '
		set -euo pipefail
		source scripts/properties.sh
		[[ "$TERMUX_APP__PACKAGE_NAME" == "$COOMI_EXPECTED_APP_PACKAGE" ]]
		[[ "$TERMUX_APP__DATA_DIR" == "$COOMI_EXPECTED_DATA_DIR" ]]
		[[ "$TERMUX__PREFIX" == "$COOMI_EXPECTED_PREFIX" ]]
		[[ "$TERMUX_PREFIX" == "$COOMI_EXPECTED_PREFIX" ]]
	'
)

printf 'prepared %s at %s\n' "$TERMUX_PACKAGES_COMMIT" "$TERMUX_DIR"
printf 'application=%s data=%s prefix=%s\n' "$COOMI_APP_PACKAGE" "$COOMI_DATA_DIR" "$COOMI_PREFIX"
