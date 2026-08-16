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
3. checks that every `.deb` has the requested architecture and `+coomi1` version
   suffix, contains no `/data/data/com.termux` path, and has AArch64 ELF files
   with a Coomi prefix RUNPATH;
4. checks that every requested root package is present; and
5. uploads the complete unsigned output and a deterministic tarball.

The current repository has static local evidence plus a bootstrap gate run;
each stage is considered built only after its GitHub Actions job produces
artifacts and logs. Signing,
repository metadata, and phone installation are separate release/runtime steps
and are deliberately not performed by this workflow.
