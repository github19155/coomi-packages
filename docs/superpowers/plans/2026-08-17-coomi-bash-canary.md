# Coomi Bash Canary Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a reproducible, unsigned Coomi-prefixed Termux `bash` canary for Android aarch64 from a pinned upstream Termux package-builder checkout.

**Architecture:** Keep this repository limited to configuration, one pinned upstream patch, shell glue, verification, and CI. Prepare a temporary upstream checkout, patch its build properties, run the official Docker wrapper, then verify every generated Debian package before uploading it as a CI artifact.

**Tech Stack:** Bash, Git, GitHub Actions, official `ghcr.io/termux/package-builder`, Debian `.deb` tooling, `file`, and `readelf`.

## Global Constraints

- Only create or modify files below `E:\ai\coomi\coomi-packages`.
- Do not modify `E:\ai\coomi` sibling projects or `D:\rust\Coomi-Android`.
- Do not commit, push, create a remote repository, sign packages, or publish a repository.
- Upstream repository is `https://github.com/termux/termux-packages.git` at commit `4dc8135244ea3909858aaf441f37cc076fe63db7`.
- Application package is `com.coomi.android`.
- Application data directory is `/data/data/com.coomi.android`.
- Prefix is `/data/data/com.coomi.android/files/usr`.
- Architecture is `aarch64`.
- Android API baseline is `24 / apt-android-7`.
- The first canary is `bash` and its locally built dependencies.
- Debian package versions contain `+coomi1`.
- Pull-request builds are unsigned and are not published to a package repository.

---

### Task 1: Repository metadata and executable static test

**Files:**
- Create: `docs/superpowers/specs/2026-08-17-coomi-bash-canary-design.md`
- Create: `docs/superpowers/plans/2026-08-17-coomi-bash-canary.md`
- Create: `config/build.env`
- Create: `README.md`
- Create: `scripts/test-static.sh`

**Interfaces:**
- `config/build.env` is sourced by Bash scripts and exposes fixed `COOMI_*` and `TERMUX_*` values.
- `scripts/test-static.sh` exits `0` only when the repository contract, shell syntax, patch markers, and workflow references are present.

- [x] **Step 1: Record the approved design and implementation plan**

  The design and plan documents define the exact upstream SHA, derived Coomi paths, Docker invocation, version suffix, verifier contract, CI policy, and non-goals.

- [ ] **Step 2: Write the failing static test**

  Create `scripts/test-static.sh` so it first checks that `config/build.env`, `patches/coomi-prefix.patch`, `scripts/prepare-termux-packages.sh`, `scripts/verify-package.sh`, and `.github/workflows/build-canary.yml` exist. It then checks their required contract markers.

- [ ] **Step 3: Run the static test and verify the expected red state**

  Run `bash scripts/test-static.sh` from the repository root. It must fail because the production files do not exist yet, rather than because of a shell syntax error.

- [ ] **Step 4: Add the fixed build environment and README**

  `config/build.env` must contain the fixed upstream URL/SHA, package identity, API level, architecture, package format, version suffix, and Docker image. `README.md` must document local preparation, CI build, verification, and the limitation that the real Docker/NDK build is only exercised by Actions.

### Task 2: Pinned upstream preparation

**Files:**
- Create: `patches/coomi-prefix.patch`
- Create: `scripts/prepare-termux-packages.sh`

**Interfaces:**
- Command: `scripts/prepare-termux-packages.sh <destination>`.
- Consumes: `config/build.env` and `patches/coomi-prefix.patch`.
- Produces: a detached upstream checkout at the exact configured commit with the patch applied and validated.

- [ ] **Step 1: Add preparation assertions to the static test**

  Assert that the script contains `git fetch --depth 1`, `git apply --check`, the exact SHA, `com.coomi.android`, and `/data/data/com.coomi.android/files/usr`; assert that it refuses a non-empty destination.

- [ ] **Step 2: Run the static test and verify the preparation assertions fail**

  Run `bash scripts/test-static.sh`. It must report the missing preparation script or its missing contract marker.

- [ ] **Step 3: Implement the preparation script**

  Resolve the repository root, source `config/build.env`, require one destination argument, reject an existing non-empty directory, initialize Git, fetch the configured SHA with depth 1, check out detached, verify `git rev-parse HEAD`, apply the patch with `git apply --check` and `git apply`, and assert the patched assignments and derived Coomi paths.

- [ ] **Step 4: Run the static test and verify the preparation contract passes**

  Run `bash scripts/test-static.sh`; the preparation assertions must pass while package verification and workflow assertions may still be pending.

### Task 3: Package verification

**Files:**
- Create: `scripts/verify-package.sh`

**Interfaces:**
- Command: `scripts/verify-package.sh <output-directory>`.
- Consumes: `.deb` files in the output directory and `config/build.env`.
- Produces: exit `0` only when all packages satisfy the control, path, architecture, and RUNPATH contract.

- [ ] **Step 1: Add verifier assertions to the static test**

  Assert that the verifier invokes `dpkg-deb --control`, `dpkg-deb --extract`, `file`, `readelf -h`, and `readelf -d`, checks `+coomi1`, and rejects `/data/data/com.termux`.

- [ ] **Step 2: Run the static test and verify the verifier assertions fail**

  Run `bash scripts/test-static.sh`; it must report the missing verifier or marker.

- [ ] **Step 3: Implement the verifier**

  Find all `.deb` files, require at least one `bash_*.deb`, extract each package into a temporary directory under the supplied output directory, and check Debian control fields. For each ELF executable or shared object, require ELF64, AArch64, and a `RUNPATH` containing `/data/data/com.coomi.android/files/usr/lib`. Scan archive bytes and extracted files for `/data/data/com.termux`.

- [ ] **Step 4: Run the static test and verify the verifier contract passes**

  Run `bash scripts/test-static.sh`; all verifier assertions must pass.

### Task 4: GitHub Actions canary workflow

**Files:**
- Create: `.github/workflows/build-canary.yml`

**Interfaces:**
- Workflow inputs: repository checkout plus values from `config/build.env`.
- Workflow outputs: unsigned verified `.deb` files uploaded as a build artifact.

- [ ] **Step 1: Add workflow assertions to the static test**

  Assert that the workflow triggers on `pull_request` and `workflow_dispatch`, calls the preparation script, runs the upstream Docker wrapper with `aarch64`, `--format debian`, `--library bionic`, and `bash`, calls the verifier, and uses `upload-artifact` without signing or repository publishing commands.

- [ ] **Step 2: Run the static test and verify the workflow assertions fail**

  Run `bash scripts/test-static.sh`; it must report the missing workflow or marker.

- [ ] **Step 3: Implement the workflow**

  Use an Ubuntu runner, check out this repository, source `config/build.env`, prepare upstream under `${RUNNER_TEMP}`, execute the official `scripts/run-docker.sh`, verify `${TERMUX_DIR}/output`, and upload the output directory. Keep the job unsigned and publish-free.

- [ ] **Step 4: Run the static test and verify the workflow contract passes**

  Run `bash scripts/test-static.sh`; all workflow assertions must pass.

### Task 5: Full local static verification

**Files:**
- Modify: `scripts/test-static.sh` only if a verified contract check needs correction.

- [ ] **Step 1: Run shell syntax checks**

  Run `find scripts -type f -name '*.sh' -print0 | xargs -0 -n1 bash -n` and require exit `0`.

- [ ] **Step 2: Run the static contract test**

  Run `bash scripts/test-static.sh` and require exit `0`.

- [ ] **Step 3: Validate the patch against the pinned upstream checkout when local Git and network are available**

  Run `scripts/prepare-termux-packages.sh` into a temporary directory inside `coomi-packages`, confirm the detached SHA and patched values, then remove only that known temporary directory. If the local machine lacks Bash or network access, record the exact skipped check instead of claiming it passed.

- [ ] **Step 4: Validate YAML syntax with an available parser**

  Use Ruby Psych, Python with PyYAML, or another installed YAML parser. If no parser is installed, run a structural check for the required workflow keys and report that a full YAML parse remains an Actions-side check.

- [ ] **Step 5: Inspect Git status and scope**

  Run `git status --short --branch` from `coomi-packages` and confirm every changed path is below that directory. Do not commit or push.
