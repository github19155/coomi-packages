# Coomi Staged Canary Implementation Plan

> **Current status:** Implemented and pushed with all six declared stage rows
> enabled. See the staged design and `config/dependency-closures.csv` for the
> current contract; successful package builds still require Actions evidence.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an explicit, manifest-backed GitHub Actions stage contract for
the Coomi runtime package groups.

**Architecture:** One workflow reads one CSV dependency-closure manifest. A stage must be present and `enabled` before the existing pinned checkout, Docker build, verifier, and unsigned artifact upload can run. Future capability rows remain `reserved` until their exact package roots and verification contracts are implemented.

**Tech Stack:** Bash, CSV, GitHub Actions, Git, the fixed Termux Docker wrapper, and the existing package verifier.

## Global Constraints

- Modify only `E:\ai\coomi\coomi-packages`.
- Do not sign packages or publish a formal package repository from this workflow.
- Keep upstream at `4dc8135244ea3909858aaf441f37cc076fe63db7`.
- Keep package identity `com.coomi.android` and prefix `/data/data/com.coomi.android/files/usr`.
- Keep architecture `aarch64`, API level `24`, baseline `apt-android-7`, Debian/bionic, and version suffix `+coomi1`.
- Keep all six declared stage rows enabled only when their exact package roots and closure entries are present.
- Do not claim that an enabled stage has produced artifacts until Actions logs and uploads prove it.

---

### Task 1: Stage manifest contract

**Files:**
- Create: `config/dependency-closures.csv`
- Modify: `config/build.env`
- Modify: `scripts/test-static.sh`

**Interfaces:**
- `config/dependency-closures.csv` exposes the exact eight-column header and one row per workflow stage.
- `config/build.env` exposes `COOMI_STAGE_MANIFEST` and the package roots for each stage.
- The static test rejects missing, duplicate, malformed, or incorrectly enabled stage rows.

- [ ] Add failing assertions for the manifest path, header, six required stages, and all enabled rows including the bootstrap roots.
- [ ] Run `bash scripts/test-static.sh` and confirm it fails because the manifest/config entries are absent.
- [ ] Add the manifest rows and configuration variables.
- [ ] Run the static test and confirm the manifest contract passes.

### Task 2: Manifest-backed Actions stage gate

**Files:**
- Modify: `.github/workflows/build-canary.yml`
- Modify: `scripts/test-static.sh`

**Interfaces:**
- `workflow_dispatch.stage` accepts `bootstrap`, `bash`, `nodejs-lts`, `python`, `uv`, and `git-openssh`.
- The validation step reads the manifest and exits before upstream preparation for any non-enabled stage.
- Every enabled stage uses the fixed Docker command, verifier, and unsigned artifact steps.

- [ ] Add failing workflow assertions for `bootstrap`, manifest loading, status rejection, and config-driven artifact naming.
- [ ] Run the static test and confirm the new workflow assertions fail.
- [ ] Implement the manifest stage gate and use `COOMI_ARTIFACT_NAME` for the unsigned artifact name.
- [ ] Run the static test and confirm the workflow contract passes.

### Task 3: Documentation and stage expansion rules

**Files:**
- Modify: `README.md`
- Modify: `docs/superpowers/specs/2026-08-17-coomi-bash-canary-design.md` only if cross-reference is needed.

**Interfaces:**
- README documents the CSV fields, status meanings, enabled stage closures, and exact requirements for adding a future stage.
- Documentation distinguishes an enabled build path from a completed build result.

- [ ] Add the stage table and manifest format to README.
- [ ] Add the staged design cross-reference if the original canary spec needs a consistency note.
- [ ] Run the static and path checks after documentation changes.

### Task 4: Full local acceptance

**Files:**
- No new files.

- [ ] Run `bash -n` on every shell script.
- [ ] Run `bash scripts/test-static.sh` and require exit 0.
- [ ] Run CSV/header/stage validation and workflow structural validation.
- [ ] Run `git status --short --branch` and verify no remote, no commit, and no paths outside the target directory.
- [ ] Report that GitHub Actions, Docker/NDK, fixed commit checkout, actual patch application, and package verification remain unrun until a remote exists.
