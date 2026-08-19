#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/config/build.env"

fail() {
	printf 'test-openssh-prefix: %s\n' "$*" >&2
	exit 1
}

PATCH_FILE="$ROOT_DIR/patches/coomi-prefix.patch"
[[ -f "$PATCH_FILE" ]] || fail "patch not found: $PATCH_FILE"
grep -Fq 'packages/openssh/sv/ssh-agent.run.in' "$PATCH_FILE" || \
	fail 'coomi-prefix.patch does not patch the openssh service template'
grep -Fq -- 'com.termux/files/usr/var/run/ssh-agent.socket' "$PATCH_FILE" || \
	fail 'patch does not identify the upstream legacy ssh-agent path'
grep -Fq -- '@TERMUX_PREFIX@/var/run/ssh-agent.socket' "$PATCH_FILE" || \
	fail 'patch does not replace the ssh-agent path with the upstream prefix placeholder'

TEST_ROOT="$(mktemp -d)"
trap 'rm -rf -- "$TEST_ROOT"' EXIT
mkdir -p "$TEST_ROOT/packages/openssh/sv"
git -C "$TEST_ROOT" init -q
printf '%s\n' \
	'#!@TERMUX_PREFIX@/bin/sh' \
	'' \
	'# Run sv-enable ssh-agent and add the following to your bashrc (or' \
	'# equivalent) to use ssh-agent:' \
	'#   export SSH_AUTH_SOCK="$PREFIX"/var/run/ssh-agent.socket' \
	'# After that you can add your key to the agent with ssh-add, and' \
	'# then make use of the credentials across all terminal sessions' \
	'' \
	'service_agent() {' \
	$'\t# If agent is not turned off before device is rebooted or' \
	$'\t# termux force-stopped, then it fails to start with:' \
	$'\t#   unix_listener: cannot bind to path /data/data/com.termux/files/usr/var/run/ssh-agent.socket: Address already in use' \
	$'\t# Therefore unlink socket file before trying to use it' \
	$'\tif [ -S "$1" ]; then' \
	$'\t\tunlink "$1"' \
	$'\tfi' \
	$'\texec ssh-agent -D -a "$1" 2>&1' \
	'}' > "$TEST_ROOT/packages/openssh/sv/ssh-agent.run.in"

git -C "$TEST_ROOT" apply --check --unidiff-zero --include='packages/openssh/sv/ssh-agent.run.in' "$PATCH_FILE" || \
	fail 'openssh service-template patch does not apply to the pinned upstream shape'
git -C "$TEST_ROOT" apply --unidiff-zero --include='packages/openssh/sv/ssh-agent.run.in' "$PATCH_FILE"
template="$TEST_ROOT/packages/openssh/sv/ssh-agent.run.in"
if grep -Fq '/data/data/com.termux' "$template"; then
	fail 'patched ssh-agent template still contains the legacy Termux path'
fi
grep -Fq '@TERMUX_PREFIX@/var/run/ssh-agent.socket' "$template" || \
	fail 'patched ssh-agent template lost the prefix placeholder'

generated="$TEST_ROOT/ssh-agent.run"
sed "s%@TERMUX_PREFIX@%$COOMI_PREFIX%g" "$template" > "$generated"
grep -Fq "$COOMI_PREFIX/var/run/ssh-agent.socket" "$generated" || \
	fail 'generated ssh-agent service does not use the Coomi socket path'
if grep -Fq '/data/data/com.termux' "$generated"; then
	fail 'generated ssh-agent service still contains the legacy Termux path'
fi

printf 'openssh Coomi prefix regression: PASS\n'
