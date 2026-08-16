# Coomi Termux Package Canary Design

## Status

Approved design. Implementation is intentionally limited to the local
`coomi-packages` repository. No commit or push is part of this phase.

## Scope

This repository owns only the Coomi build metadata, one upstream patch, the
preparation and verification scripts, and the GitHub Actions entry point. It
does not vendor `termux/termux-packages`.

The first canary builds `bash` and its dependency graph for Android aarch64
using the official Termux package-builder Docker image and Android NDK
toolchain. Node.js and Python are outside this phase.

## Fixed Contract

| Property | Value |
| --- | --- |
| Upstream repository | `https://github.com/termux/termux-packages.git` |
| Upstream commit | `4dc8135244ea3909858aaf441f37cc076fe63db7` |
| Application package | `com.coomi.android` |
| Application data directory | `/data/data/com.coomi.android` |
| Prefix | `/data/data/com.coomi.android/files/usr` |
| Architecture | `aarch64` |
| Android API level | `24` |
| Android baseline label | `apt-android-7` |
| Package format | `debian` |
| Package library | `bionic` |
| Version marker | `+coomi1` |
| First package | `bash` |

The upstream build system consumes API level `24` through
`TERMUX_PKG_API_LEVEL`; `apt-android-7` is recorded as the corresponding
baseline label rather than invented as an upstream variable.

## Architecture

GitHub Actions checks out this repository, clones the pinned upstream commit
into the runner temporary directory, applies `patches/coomi-prefix.patch`,
and verifies the resulting checkout before invoking the upstream
`scripts/run-docker.sh` wrapper. The Docker wrapper mounts only the temporary
upstream checkout. The local repository remains the small source of truth.

The build command is equivalent to:

```text
./scripts/run-docker.sh ./build-package.sh -a aarch64 --format debian --library bionic bash
```

Dependency installation flags are deliberately omitted. A clean canary must
compile the dependency graph with the same Coomi prefix instead of extracting
official prebuilt packages that may contain Termux paths.

## Patch Boundary

The patch changes only upstream build properties and version assembly:

- Set `TERMUX_APP__PACKAGE_NAME` and the repository identity paths to Coomi.
- Keep the upstream derived rootfs and prefix layout so the resulting prefix
  is exactly `/data/data/com.coomi.android/files/usr`.
- Change the actual CGCT paths used by the build properties to Coomi.
- Append `+coomi1` to `TERMUX_PKG_FULLVERSION` after the upstream revision
  logic. Debian output is the only format in this phase.

The patch does not rename the upstream project, internal `termux` directory,
package names, or Java namespaces. Those are separate application fork work
and are not needed to produce the first package canary.

## Verification Contract

`scripts/verify-package.sh` scans every `.deb` in the output directory. It
uses `dpkg-deb` to read control metadata and unpack data, `grep` to reject
`/data/data/com.termux`, `file` to identify target binaries, and `readelf` to
validate ELF64 AArch64 files and their dynamic `RUNPATH`.

The verifier requires a bash package, a Coomi version suffix, aarch64 package
metadata, no legacy Termux data path in package bytes or extracted paths, and
the Coomi library prefix in each dynamic ELF RUNPATH.

## CI Policy

The workflow runs for pull requests and manual dispatch. It does not sign,
publish, or update a package repository. It uploads only the unsigned canary
artifacts after verification.

## Non-goals

- No remote repository creation.
- No signing keys or release metadata.
- No changes to the Android application project.
- No Node.js or Python canaries.
- No vendored upstream source.
