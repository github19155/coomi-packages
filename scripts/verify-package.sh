#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/config/build.env"

fail() {
	printf 'verify-package: %s\n' "$*" >&2
	exit 1
}

if [[ $# -lt 2 ]]; then
	fail "usage: $0 <output-directory> <expected-package> [expected-package ...]"
fi

OUTPUT_DIR="$1"
shift
EXPECTED_PACKAGES=("$@")
[[ -d "$OUTPUT_DIR" ]] || fail "output directory not found: $OUTPUT_DIR"
command -v dpkg-deb >/dev/null || fail "dpkg-deb is required"
command -v file >/dev/null || fail "file is required"
command -v readelf >/dev/null || fail "readelf is required"
command -v readlink >/dev/null || fail "readlink is required"

mapfile -t packages < <(find "$OUTPUT_DIR" -maxdepth 1 -type f -name '*.deb' -print | sort)
(( ${#packages[@]} > 0 )) || fail "no .deb files found in $OUTPUT_DIR"

LEGACY_PREFIX="/data/data/com.termux"
VERIFY_DIR="$(mktemp -d "$OUTPUT_DIR/.coomi-verify.XXXXXX")"
trap 'rm -rf -- "$VERIFY_DIR"' EXIT

elf_count=0
declare -A seen_packages=()

for package in "${packages[@]}"; do
	base_name="$(basename -- "$package")"
	if LC_ALL=C grep -aFq -- "$LEGACY_PREFIX" "$package"; then
		fail "$base_name contains legacy path $LEGACY_PREFIX"
	fi

	control_dir="$VERIFY_DIR/$base_name-control"
	data_dir="$VERIFY_DIR/$base_name-data"
	mkdir -p "$control_dir" "$data_dir"
	dpkg-deb --control "$package" "$control_dir"
	dpkg-deb --extract "$package" "$data_dir"

	[[ -f "$control_dir/control" ]] || fail "$base_name has no control file"
	package_name="$(dpkg-deb -f "$package" Package)"
	architecture="$(dpkg-deb -f "$package" Architecture)"
	version="$(dpkg-deb -f "$package" Version)"
	[[ -n "$package_name" ]] || fail "$base_name has no package name"
	seen_packages["$package_name"]=1
	[[ "$architecture" == "$TERMUX_ARCH" || "$architecture" == "all" ]] || \
		fail "$base_name architecture is $architecture, expected $TERMUX_ARCH or all"
	[[ "$version" == *"$COOMI_VERSION_SUFFIX" ]] || fail "$base_name version lacks $COOMI_VERSION_SUFFIX: $version"

	while IFS= read -r -d '' file_path; do
		if LC_ALL=C grep -aFq -- "$LEGACY_PREFIX" "$file_path"; then
			fail "$base_name extracted file contains legacy path $LEGACY_PREFIX: $file_path"
		fi
	done < <(find "$control_dir" "$data_dir" -type f -print0)

	while IFS= read -r -d '' link_path; do
		link_target="$(readlink -- "$link_path")"
		if [[ "$link_target" == *"$LEGACY_PREFIX"* ]]; then
			fail "$base_name symlink target contains legacy path $LEGACY_PREFIX: $link_path -> $link_target"
		fi
	done < <(find "$control_dir" "$data_dir" -type l -print0)

	while IFS= read -r -d '' file_path; do
		file_info="$(file -b -- "$file_path")"
		[[ "$file_info" == *ELF* ]] || continue
		((elf_count += 1))
		[[ "$file_info" == *"ELF 64-bit"* ]] || fail "$file_path is not ELF64: $file_info"
		[[ "$file_info" == *"ARM aarch64"* ]] || fail "$file_path is not AArch64: $file_info"

		header="$(readelf -h -- "$file_path")"
		grep -Eq 'Class:[[:space:]]+ELF64' <<< "$header" || fail "$file_path has the wrong ELF class"
		grep -Eq 'Machine:[[:space:]]+AArch64' <<< "$header" || fail "$file_path has the wrong ELF machine"

		if [[ "$file_info" == *executable* || "$file_info" == *"shared object"* ]]; then
			dynamic="$(readelf -d -- "$file_path" 2>/dev/null || true)"
			if grep -Eq '\((RPATH|RUNPATH)\)' <<< "$dynamic"; then
				if LC_ALL=C grep -aFq -- "$LEGACY_PREFIX" <<< "$dynamic"; then
					fail "$file_path RPATH/RUNPATH contains legacy path $LEGACY_PREFIX"
				fi
				while IFS= read -r app_path; do
					[[ -n "$app_path" ]] || continue
					[[ "$app_path" == "$COOMI_PREFIX" || "$app_path" == "$COOMI_PREFIX/"* ]] || \
						fail "$file_path RPATH/RUNPATH contains a non-Coomi app path: $app_path"
				done < <(grep -oE '/data/data/[^][[:space:]:]+' <<< "$dynamic" || true)
			fi
		fi
	done < <(find "$control_dir" "$data_dir" -type f -print0)
done

for expected_package in "${EXPECTED_PACKAGES[@]}"; do
	[[ "${seen_packages[$expected_package]+yes}" == yes ]] || \
		fail "expected package was not generated: $expected_package"
done
(( elf_count > 0 )) || fail "no ELF files found in package set"

printf 'verified %d package(s), %d ELF file(s), target=%s, prefix=%s\n' \
	"${#packages[@]}" "$elf_count" "$TERMUX_ARCH" "$COOMI_PREFIX"
