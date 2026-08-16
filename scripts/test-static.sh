#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

required_paths=(
	"config/build.env"
	"config/dependency-closures.csv"
	"patches/coomi-prefix.patch"
	"scripts/prepare-termux-packages.sh"
	"scripts/verify-package.sh"
	".github/workflows/build-canary.yml"
)

for path in "${required_paths[@]}"; do
	[[ -f "$ROOT_DIR/$path" ]] || {
		printf 'missing required path: %s\n' "$path" >&2
		exit 1
	}
done

source "$ROOT_DIR/config/build.env"

[[ "${TERMUX_PACKAGES_COMMIT:-}" == "4dc8135244ea3909858aaf441f37cc076fe63db7" ]]
[[ "${COOMI_APP_PACKAGE:-}" == "com.coomi.android" ]]
[[ "${COOMI_DATA_DIR:-}" == "/data/data/com.coomi.android" ]]
[[ "${COOMI_PREFIX:-}" == "/data/data/com.coomi.android/files/usr" ]]
[[ "${TERMUX_ARCH:-}" == "aarch64" ]]
[[ "${TERMUX_PKG_API_LEVEL:-}" == "24" ]]
[[ "${COOMI_VERSION_SUFFIX:-}" == "+coomi1" ]]
[[ "${COOMI_STAGE_MANIFEST:-}" == "config/dependency-closures.csv" ]]
[[ "${COOMI_BOOTSTRAP_PACKAGES:-}" == "bash apt dpkg" ]]
[[ "${COOMI_NODEJS_PACKAGES:-}" == "nodejs-lts npm" ]]
[[ "${COOMI_PYTHON_PACKAGES:-}" == "python python-pip" ]]
[[ "${COOMI_UV_PACKAGES:-}" == "uv" ]]
[[ "${COOMI_GIT_PACKAGES:-}" == "git openssh" ]]

manifest_file="$ROOT_DIR/$COOMI_STAGE_MANIFEST"
[[ -f "$manifest_file" ]]
grep -Fxq 'stage,status,package_group,root_packages,declared_dependencies,closure_source,build_policy,artifact_policy' "$manifest_file"
awk -F, 'NR > 1 && NF != 8 { exit 1 }' "$manifest_file"

required_stages=(bootstrap bash nodejs-lts python uv git-openssh)
for stage in "${required_stages[@]}"; do
	awk -F, -v stage="$stage" 'NR > 1 && $1 == stage { count += 1 } END { exit count == 1 ? 0 : 1 }' "$manifest_file"
done

bash_row="$(awk -F, '$1 == "bash" { print; exit }' "$manifest_file")"
[[ "$bash_row" == bash,enabled,bash,bash,* ]]
bootstrap_row="$(awk -F, '$1 == "bootstrap" { print; exit }' "$manifest_file")"
[[ "$bootstrap_row" == bootstrap,enabled,bootstrap,bash\|apt\|dpkg,* ]]
enabled_count="$(awk -F, 'NR > 1 && $2 == "enabled" { count += 1 } END { print count + 0 }' "$manifest_file")"
[[ "$enabled_count" == "6" ]]
for stage in "${required_stages[@]}"; do
	awk -F, -v stage="$stage" 'NR > 1 && $1 == stage && $2 == "enabled" { found = 1 } END { exit found ? 0 : 1 }' "$manifest_file"
done

while IFS= read -r -d '' script; do
	bash -n "$script"
done < <(find "$ROOT_DIR/scripts" -type f -name '*.sh' -print0)

patch_file="$ROOT_DIR/patches/coomi-prefix.patch"
grep -Fq 'TERMUX_APP__PACKAGE_NAME="com.coomi.android"' "$patch_file"
grep -Fq 'TERMUX_PKG_FULLVERSION+="+coomi1"' "$patch_file"

prepare_file="$ROOT_DIR/scripts/prepare-termux-packages.sh"
grep -Fq 'git fetch --depth 1 origin "$TERMUX_PACKAGES_COMMIT"' "$prepare_file"
grep -Fq 'git apply --check' "$prepare_file"
grep -Fq 'TERMUX_DIR="$(cd -- "$TERMUX_DIR" && pwd)"' "$prepare_file"
grep -Fq 'com.coomi.android' "$prepare_file"
grep -Fq '/data/data/com.coomi.android/files/usr' "$prepare_file"

verify_file="$ROOT_DIR/scripts/verify-package.sh"
grep -Fq 'dpkg-deb --control' "$verify_file"
grep -Fq 'dpkg-deb --extract' "$verify_file"
grep -Fq 'file -b' "$verify_file"
grep -Fq 'readelf -h' "$verify_file"
grep -Fq 'readelf -d' "$verify_file"
grep -Fq 'COOMI_VERSION_SUFFIX' "$verify_file"
grep -Fq '/data/data/com.termux' "$verify_file"

workflow_file="$ROOT_DIR/.github/workflows/build-canary.yml"
grep -Fq 'pull_request:' "$workflow_file"
grep -Fq 'workflow_dispatch:' "$workflow_file"
grep -Fq -- '- bootstrap' "$workflow_file"
grep -Fq 'COOMI_BOOTSTRAP_PACKAGES' "$workflow_file"
grep -Fq 'COOMI_NODEJS_PACKAGES' "$workflow_file"
grep -Fq 'COOMI_PYTHON_PACKAGES' "$workflow_file"
grep -Fq 'COOMI_UV_PACKAGES' "$workflow_file"
grep -Fq 'COOMI_GIT_PACKAGES' "$workflow_file"
grep -Fq 'COOMI_BUILD_PACKAGES' "$workflow_file"
grep -Fq 'COOMI_EXPECTED_PACKAGES' "$workflow_file"
grep -Fq 'COOMI_STAGE_MANIFEST' "$workflow_file"
grep -Fq 'manifest_status' "$workflow_file"
grep -Fq 'configured_roots' "$workflow_file"
grep -Fq 'build_packages="${build_packages//|/ }"' "$workflow_file"
grep -Fq 'COOMI_ARTIFACT_NAME}-unsigned' "$workflow_file"
grep -Fq 'build_package_args' "$workflow_file"
grep -Fq 'bash scripts/prepare-termux-packages.sh "$TERMUX_DIR"' "$workflow_file"
grep -Fq 'scripts/run-docker.sh' "$workflow_file"
grep -Fq -- '--format debian' "$workflow_file"
grep -Fq -- '--library bionic' "$workflow_file"
grep -Fq -- ' bash' "$workflow_file"
grep -Fq 'bash "$GITHUB_WORKSPACE/scripts/verify-package.sh"' "$workflow_file"
grep -Fq 'expected-package' "$verify_file"
grep -Fq 'upload-artifact' "$workflow_file"
if grep -Eiq '(^|[[:space:]])(gpg|apksigner|dpkg-sig|aptly|reprepro)([[:space:]]|$)|(^|[[:space:]])publish([[:space:]]|$)' "$workflow_file"; then
	printf 'workflow contains a forbidden signing or publishing command\n' >&2
	exit 1
fi

printf 'static repository contract: PASS\n'
