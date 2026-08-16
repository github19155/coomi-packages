# Coomi Staged Termux Canary Design

## Status

Implemented locally. This change organizes the staged GitHub Actions entry
points and dependency-closure contract. It does not create a remote or push.

## Goal

Provide reproducible entry points for Coomi bootstrap, Node.js/npm,
Python/pip, uv/uvx, and Git/OpenSSH, while keeping actual success claims tied
to completed GitHub Actions runs.

## Architecture

The repository keeps one GitHub Actions workflow and one machine-readable
dependency-closure manifest. The workflow dispatch input lists every planned
stage, then reads the manifest before preparation. Only a row with
`status=enabled` may reach the Docker build; `reserved` and `disabled` rows
exit before checkout/build artifact creation.

The enabled `bash` row has one exact package root. The reserved rows record
package IDs confirmed in the fixed upstream tree, but they cannot reach the
Docker build. When a row is enabled, the upstream `build-package.sh`
dependency graph must build dependencies from the patched Coomi checkout. The
build does not use `-i` or `-I`, so it cannot silently consume Termux prebuilt
dependencies.

## Fixed Stage Contract

| Stage | Status | Package group | Current behavior |
| --- | --- | --- | --- |
| `bootstrap` | `reserved` | bootstrap staging | No standalone Termux package; the bash canary may produce a staging tarball |
| `bash` | `enabled` | bash and recursive dependencies | Real Docker/NDK canary |
| `nodejs-lts` | `reserved` | Node.js LTS and npm | Roots are `nodejs-lts` and `npm`; npm installs npm and npx |
| `python` | `reserved` | Python and pip | Roots are `python` and `python-pip` |
| `uv` | `reserved` | uv and uvx | The uv package installs both binaries |
| `git-openssh` | `reserved` | Git and OpenSSH | Roots are `git` and `openssh` |

## Dependency Closure Manifest

`config/dependency-closures.csv` uses a fixed eight-column format:

```text
stage,status,package_group,root_packages,declared_dependencies,closure_source,build_policy,artifact_policy
```

Rules:

- `stage` is the exact workflow dispatch value.
- `status` is one of `enabled`, `reserved`, or `disabled`.
- `package_group` is the user-facing capability group.
- `root_packages` contains exact Termux package IDs when known; `-` is used for the non-package bootstrap row.
- `declared_dependencies` records direct dependency/recommendation names from the referenced upstream build definitions; `-` is used when no package exists.
- `closure_source` names the pinned upstream commit and exact build definition paths.
- `build_policy` states whether dependencies are built from the Coomi checkout; reserved rows use `reserved-no-build`.
- `artifact_policy` identifies the verified artifact contract; `none` is used for non-enabled rows.

The manifest is deliberately CSV rather than a second YAML dialect so Bash,
PowerShell, and Actions can validate it without adding a parser dependency.
The workflow and static test validate the header, stage uniqueness, the single
enabled `bash` row, and the reserved future rows. The npm definition at this
commit installs both `npm` and `npx`; `uv` installs both `uv` and `uvx`.

## Actions Flow

1. Check out this repository.
2. Load `config/build.env` and the stage manifest.
3. Reject unknown, reserved, or disabled stages before upstream preparation.
4. For `bash`, fetch the fixed upstream commit, apply the Coomi patch, and run the official
   `scripts/run-docker.sh -m ./build-package.sh` wrapper with
   aarch64, Debian, bionic, and API 24 inputs.
5. Verify every generated `.deb`, reject legacy Termux paths, and upload only
   verified unsigned `.deb` files plus the unsigned bootstrap staging bundle.

No signing key, release repository, or formal package publication is part of
this workflow.

## Verification Boundary

Local checks cover shell syntax, manifest shape, required workflow markers,
path substitution, and patch parseability. The actual Linux runner must still
validate GitHub's YAML parser, Docker privileges, GHCR image access, fixed
commit checkout, patch application, recursive dependency compilation, Debian
metadata, ELF architecture, RUNPATH, and artifact contents.
