# Staged package builds

GitHub Actions is the reproducible build boundary. The dispatch stage is
checked against `config/dependency-closures.csv` before any upstream checkout.
All six declared rows are currently enabled. Each selected row must match its
configured roots before preparation and can then enter the recursive local
dependency build and artifact verifier.

| Stage | Status | Package roots | Runtime commands supplied |
| --- | --- | --- | --- |
| `bash` | enabled | `bash` | `bash` |
| `bootstrap` | enabled | `bash`, `apt`, `dpkg` | bootstrap shell and package manager |
| `nodejs-lts` | enabled | `nodejs-lts`, `npm` | `node`, `npm`, `npx` |
| `python` | enabled | `python`, `python-pip` | `python`, `pip` |
| `uv` | enabled | `uv` | `uv`, `uvx` |
| `git-openssh` | enabled | `git`, `openssh` | `git`, `ssh`, `scp`, `sftp` |

The package roots and direct declarations are recorded in
`config/dependency-closures.csv`. They are intentionally not a hand-written
transitive closure: dependency versions and additional runtime libraries are
resolved by the pinned upstream build graph when a row is enabled. The output
must therefore be retained as a complete set, including packages generated for
subpackages such as OpenSSH's SFTP server.

## Verification contract

For an enabled stage the workflow:

1. fetches the exact upstream commit and applies `patches/coomi-prefix.patch`;
2. builds all selected roots with `-a aarch64 --format debian --library bionic`;
3. checks that every `.deb` has `Architecture: aarch64` or Debian's
   architecture-independent `Architecture: all`, has the `+coomi1` version
   suffix, and contains no `/data/data/com.termux` path. Every ELF inside
   either package type must still be ELF64/AArch64. If an ELF has an `RPATH`
   or `RUNPATH`, it must not contain the legacy Termux path or an app data path
   outside the Coomi prefix; missing tags are allowed;
4. checks that every requested root package is present; and
5. always uploads a diagnostic artifact when package output exists, while the
   verified unsigned output and deterministic tarball are uploaded only after
   the verifier succeeds. The diagnostic artifact is a tar.gz archive so
   original Debian filenames, including epoch `:` characters, are preserved.

The current repository has static local evidence plus a bootstrap gate run;
each stage is considered built only after its GitHub Actions job produces
artifacts and logs. Signing,
repository metadata, and phone installation are separate release/runtime steps
and are deliberately not performed by this workflow.
