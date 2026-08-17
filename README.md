# coomi-packages

This is the small Coomi-specific Termux package build repository. It does not
vendor the Termux source tree. GitHub Actions fetches the pinned upstream
commit at build time, applies the local Coomi patch, and runs the official
Termux Docker/NDK build system.

## Fixed canary

- Upstream: `termux/termux-packages` at
  `4dc8135244ea3909858aaf441f37cc076fe63db7`
- Application package: `com.coomi.android`
- Data directory: `/data/data/com.coomi.android`
- Prefix: `/data/data/com.coomi.android/files/usr`
- Target: `aarch64`
- Android API level: `24` (`apt-android-7` baseline)
- Package format/library: Debian / bionic
- Version marker: `+coomi1`
- Bootstrap roots: `bash`, `apt`, and `dpkg`
- Staged roots: `bash`, `nodejs-lts`/`npm`, `python`/`python-pip`, `uv`, and
  `git`/`openssh`

The current repository has no signing keys, release repository, or publish
job. Pull requests and manual runs produce unsigned inspection artifacts only.

The official image's restricted AppArmor profile keeps `/home/builder/lib`
read-only. The workflow therefore creates a writable SDK root at
`/home/builder/.termux-build/coomi-android-sdk-9123335`, copies the official
command-line tools into it, and installs the pinned `platforms;android-33` and
`build-tools;30.0.3` components. The SDK check and package build run as the
normal `builder` user. This is container-local state; no host `.termux-build`
volume or Actions cache is used.

## Repository layout

```text
config/build.env                 Fixed build inputs
patches/coomi-prefix.patch       Pinned upstream property/version patch
scripts/prepare-termux-packages.sh
                                  Fetch and patch the exact upstream commit
scripts/verify-package.sh        Inspect every generated .deb
scripts/test-static.sh           Local contract and shell syntax check
.github/workflows/build-canary.yml
                                  The only formal build entry point
```

## Formal build path

The supported build path is GitHub Actions. It runs on Ubuntu, keeps Docker's
build directories container-local, fetches the pinned upstream checkout into
the runner workspace, and invokes the selected package roots through:

```text
./scripts/run-docker.sh ./build-package.sh -a aarch64 \
  --format debian --library bionic bash
```

The workflow supports `workflow_dispatch`. Its stage input exposes `bash`,
`bootstrap`, `nodejs-lts`, `python`, `uv`, and `git-openssh`. The stage gate
reads `config/dependency-closures.csv`; all six declared rows are currently
`enabled`, and the selected row must match its configured package roots before
upstream preparation. A stage is not considered successful until its GitHub
Actions artifacts and logs have been inspected.

After the build, the workflow runs `scripts/verify-package.sh`, uploads every
unsigned `.deb`, and uploads a deterministic unsigned stage bundle containing
those `.deb` files. The bundle is an inspection artifact, not yet an
installable Android bootstrap zip.

## Local static checks

On a machine with Bash, run from this repository:

```bash
bash scripts/test-static.sh
```

The check validates fixed values, shell syntax, patch/script contracts, and
workflow structure. The real Docker/NDK cross-build is intentionally left to
GitHub Actions; this Windows workspace does not claim that build has run.

To validate the pinned patch locally when Git and network access are available:

```bash
scripts/prepare-termux-packages.sh .local-termux-packages
```

The preparation script rejects non-empty destinations and prints the exact
detached upstream SHA after applying the patch. Remove that temporary directory
only after inspection.

## Staged package groups

`config/dependency-closures.csv` is the source of truth for the stage matrix.
It records exact package roots and the direct runtime/build/recommendation
declarations observed at the fixed upstream commit.
The upstream `build-package.sh` resolves the transitive closure from the
patched Coomi checkout; no `-i` or `-I` prebuilt dependency mode is used.

| Stage | Status | Fixed upstream roots | Notes |
| --- | --- | --- | --- |
| `bash` | enabled | `bash` | Shell and recursive dependencies |
| `bootstrap` | enabled | `bash`, `apt`, `dpkg` | Bootstrap package roots and recursive dependencies |
| `nodejs-lts` | enabled | `nodejs-lts`, `npm` | `npm` is separate and provides both `npm` and `npx` binaries |
| `python` | enabled | `python`, `python-pip` | `pip` is supplied by `python-pip` |
| `uv` | enabled | `uv` | The `uv` package installs both `uv` and `uvx` |
| `git-openssh` | enabled | `git`, `openssh` | Git recommends OpenSSH; both roots are recorded |

`enabled` means the stage may enter the pinned checkout, recursive local
dependency build, verifier, and unsigned artifact upload. It does not claim a
successful package build before a completed Actions run provides logs and
artifacts.
