#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/config/build.env"

LEGACY_PREFIX="/data/data/com.termux"

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
	local link_mode="${5:-coomi-runpath}"
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
	elif [[ "$payload" == dangling ]]; then
		ln -s /coomi/does-not-exist "$package_dir/usr/bin/$package_name"
	elif [[ "$payload" == legacy-symlink ]]; then
		ln -s "$LEGACY_PREFIX/files/usr/bin/termux" "$package_dir/usr/bin/$package_name"
	else
		link_flags=()
		case "$link_mode" in
			coomi-runpath)
				link_flags=(-Wl,-rpath,"$COOMI_PREFIX/lib")
				;;
			no-runpath)
				;;
			shared-no-runpath)
				link_flags=(-shared -fPIC)
				;;
			wrong-app-runpath)
				link_flags=(-Wl,-rpath,/data/data/com.other.android/files/usr/lib)
				;;
			legacy-runpath)
				link_flags=(-Wl,-rpath,/data/data/com.termux/files/usr/lib)
				;;
			*)
				fail "unknown link mode: $link_mode"
				;;
		esac
		"$payload" "${link_flags[@]}" -o "$package_dir/usr/bin/$package_name" "$SOURCE_FILE"
		chmod 0755 "$package_dir/usr/bin/$package_name"
	fi
	dpkg-deb --build "$package_dir" "$output_dir/$package_name.deb" >/dev/null
}

valid_output="$TEST_ROOT/valid-output"
build_package coomi-all all script "$valid_output"
build_package coomi-dangling all dangling "$valid_output"
build_package coomi-aarch64 aarch64 aarch64-linux-gnu-gcc "$valid_output" coomi-runpath
build_package coomi-aarch64-shared-no-runpath aarch64 aarch64-linux-gnu-gcc "$valid_output" shared-no-runpath
if ! valid_log="$($ROOT_DIR/scripts/verify-package.sh "$valid_output" coomi-all coomi-dangling coomi-aarch64 coomi-aarch64-shared-no-runpath 2>&1)"; then
	printf '%s\n' "$valid_log" >&2
	fail 'Architecture: all package was rejected'
fi
[[ "$valid_log" == *'verified 4 package(s), 2 ELF file(s)'* ]] ||
	fail 'valid Architecture: all verification output was incomplete'
[[ "$valid_log" != *'No such file'* ]] ||
	fail 'dangling symlink produced a recursive traversal error'

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

bad_rpath_output="$TEST_ROOT/bad-rpath-output"
build_package coomi-wrong-app-rpath aarch64 aarch64-linux-gnu-gcc "$bad_rpath_output" wrong-app-runpath
bad_rpath_log="$TEST_ROOT/bad-rpath.log"
if "$ROOT_DIR/scripts/verify-package.sh" "$bad_rpath_output" coomi-wrong-app-rpath >"$bad_rpath_log" 2>&1; then
	fail 'ELF with a non-Coomi app RUNPATH was accepted'
fi
grep -Fq 'contains a non-Coomi app path' "$bad_rpath_log" || {
	cat "$bad_rpath_log" >&2
	fail 'non-Coomi app RUNPATH failed without the expected diagnostic'
}

legacy_rpath_output="$TEST_ROOT/legacy-rpath-output"
build_package coomi-legacy-rpath aarch64 aarch64-linux-gnu-gcc "$legacy_rpath_output" legacy-runpath
legacy_rpath_log="$TEST_ROOT/legacy-rpath.log"
if "$ROOT_DIR/scripts/verify-package.sh" "$legacy_rpath_output" coomi-legacy-rpath >"$legacy_rpath_log" 2>&1; then
	fail 'ELF with a legacy Termux RUNPATH was accepted'
fi
grep -Fq 'contains legacy path /data/data/com.termux' "$legacy_rpath_log" || {
	cat "$legacy_rpath_log" >&2
	fail 'legacy Termux RUNPATH failed without the expected diagnostic'
}

legacy_symlink_output="$TEST_ROOT/legacy-symlink-output"
build_package coomi-legacy-symlink all legacy-symlink "$legacy_symlink_output"
legacy_symlink_log="$TEST_ROOT/legacy-symlink.log"
if "$ROOT_DIR/scripts/verify-package.sh" "$legacy_symlink_output" coomi-legacy-symlink >"$legacy_symlink_log" 2>&1; then
	fail 'symlink target containing the legacy Termux path was accepted'
fi
grep -Fq 'contains legacy path /data/data/com.termux' "$legacy_symlink_log" || {
	cat "$legacy_symlink_log" >&2
	fail 'legacy symlink target failed without the expected diagnostic'
}

printf 'verify-package regression tests: PASS\n'
