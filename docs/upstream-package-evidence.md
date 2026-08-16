# Upstream package evidence

The package definitions below were checked against the pinned upstream commit
`termux-packages@4dc8135244ea3909858aaf441f37cc076fe63db7` in the corresponding
`packages/<name>/build.sh` files. Versions are informational; the build uses
the checked-out scripts, not these copied values.

| Root | Upstream version | Declared runtime dependencies | Notes |
| --- | --- | --- | --- |
| `bash` | `5.3.15` | `libandroid-support`, `libiconv`, `readline`, `termux-tools` | bootstrap shell |
| `apt` | `2.8.1-2` | `dpkg`, crypto/compression libraries, `termux-keyring` and core utilities | essential package manager |
| `dpkg` | `1.22.6-5` | compression, archive, pager and core utilities | essential package database |
| `nodejs-lts` | `24.18.0-1` | `libc++`, `openssl`, `c-ares`, `libicu`, `libsqlite`, `zlib` | recommends `npm` |
| `npm` | `11.19.0` | `nodejs` or `nodejs-lts` | provides npm/npx scripts |
| `python` | `3.14.6-1` | gdbm, crypto, sqlite, compression, readline and Android support libraries | recommends `python-pip` |
| `python-pip` | `26.2.1` | `python (>= 3.11.1-1)` | pip is separate from Python |
| `uv` | `0.12.5` | `zstd` | package installs both `uv` and `uvx` |
| `git` | `2.55.0` | curl, expat, iconv, less, OpenSSL, PCRE2, zlib | recommends OpenSSH |
| `openssh` | `10.5p1` | Kerberos, LDNS, libedit, OpenSSL, auth and SFTP subpackage | emits SFTP subpackage |

All six stage rows are enabled manifest roots, with `bash`, `apt`, and `dpkg`
forming the bootstrap root set. Enabling a row is a build-path claim, not a
successful-build claim: the builder must still resolve and compile the
transitive dependencies on Actions. The builder emits those dependencies in
the same output directory. Therefore the manifest is a list of roots and a
policy, not an attempt to freeze a manually maintained closure.
The upstream commit, local patch, package roots, architecture, API level, and
library mode are the reproducibility inputs.
