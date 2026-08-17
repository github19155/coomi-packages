#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/config/build.env"

fail() {
	printf 'test-verify-package: %s\n' "$*" >&2
	exit 1
}

for command_name in dpkg-deb file readelf gcc aarch64-linux-gnu-gcc; do
	command -v "$command_name" >/dev/null || fail "$command_name is required"
done

TEST_ROOT="$(mktemp -d)"
trap 'rm -rf -- "$TEST_ROOT"' EXIT
SOURCE_FILE="$TEST_ROOT/hello.c"
cat > "$SOURCE_FILE" <<'EOF'
int main(void) {
	return 0;
}
EOF

build_package() {
	local package_name="$1"
	local architecture="$2"
	local payload="$3"
	local output_dir="$4"
	local package_dir="$TEST_ROOT/$package_name"

	mkdir -p "$package_dir/DEBIAN" "$package_dir/usr/bin" "$output_dir"
	cat > "$package_dir/DEBIAN/control" <<EOF
Package: $package_name
Version: 1.0+coomi1
Architecture: $architecture
Maintainer: Coomi CI <ci@coomi.invalid>
Description: verifier regression fixture
 Test fixture for the Coomi package verifier.
EOF
	if [[ "$payload" == script ]]; then
		printf '#!/system/bin/sh\nprintf all-package\n' > "$package_dir/usr/bin/$package_name"
		chmod 0755 "$package_dir/usr/bin/$package_name"
	else
		"$payload" -Wl,-rpath,"$COOMI_PREFIX/lib" -o "$package_dir/usr/bin/$package_name" "$SOURCE_FILE"
		chmod 0755 "$package_dir/usr/bin/$package_name"
	fi
	dpkg-deb --build "$package_dir" "$output_dir/$package_name.deb" >/dev/null
}

valid_output="$TEST_ROOT/valid-output"
build_package coomi-all all script "$valid_output"
build_package coomi-aarch64 aarch64 aarch64-linux-gnu-gcc "$valid_output"
if ! valid_log="$($ROOT_DIR/scripts/verify-package.sh "$valid_output" coomi-all coomi-aarch64 2>&1)"; then
	printf '%s\n' "$valid_log" >&2
	fail 'Architecture: all package was rejected'
fi
[[ "$valid_log" == *'verified 2 package(s), 1 ELF file(s)'* ]] ||
	fail 'valid Architecture: all verification output was incomplete'

invalid_output="$TEST_ROOT/invalid-output"
build_package coomi-wrong-elf aarch64 gcc "$invalid_output"
invalid_log="$TEST_ROOT/invalid.log"
if "$ROOT_DIR/scripts/verify-package.sh" "$invalid_output" coomi-wrong-elf >"$invalid_log" 2>&1; then
	fail 'wrong-architecture ELF was accepted'
fi
grep -Fq 'is not AArch64' "$invalid_log" || {
	cat "$invalid_log" >&2
	fail 'wrong-architecture ELF failed without the expected diagnostic'
}

printf 'verify-package regression tests: PASS\n'
