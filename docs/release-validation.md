# MVP 0.4.0 validation — 2026-10-04

The implementation is ready for a local MVP release on the tested arm64 environments. No tag, remote push, package publication, or hosted CI run was performed. This checkout has no Git remote configured.

## Executed release gate

`ruby script/ci.rb` passed in both environments, using Spinel source revision `6c97683140c624520836c8f807ba598f0f47a57e`:

| Environment | C compiler | CRuby reference | Result |
| --- | --- | --- | --- |
| macOS 26.6.2, arm64 | Apple clang 21.0.0 | Ruby 4.1.0dev, revision `332315a464` | Passed |
| Debian Bookworm, aarch64, Docker | GCC 12.2.0 | Ruby 3.4.2 | Passed |

Each environment passed seven unit programs compared with CRuby and 137 native integration checks: M1 45, M2 19, M3 47, M4 26. The gate also compiled and ran the documented integer, Boolean/array suite, exact-selector, and deliberately buggy examples, checking pass/failure/error exits explicitly.

The M4 package test copies the source into a clean directory, builds a native package, hides the source directory, moves the package to a path containing spaces and an apostrophe, and invokes its builder through a PATH symlink. After compilation it hides the package and spec sources, removes Ruby/Spinel from PATH, and verifies both the failing runner and its exact printed replay command. The mutation-using array target still reduces to `[3]`.

The Linux compiler was built from an archive of the pinned source and its local vendored parser sources in `ruby:3.4.2-bookworm`. Hypo's release tests then ran with container networking disabled. This exercises Linux arm64; it is not a test of every Linux distribution or an emulated x86 build.

## CI definition and remaining external check

`.github/workflows/ci.yml` pins checkout, Ruby setup, and artifact-upload actions by commit, Ruby to 3.4.2, and Spinel to the full revision above. It builds Spinel from source and invokes the same release gate on `macos-14` and `ubuntu-24.04-arm`. Both are arm64 labels in the [GitHub runner reference](https://docs.github.com/en/actions/reference/runners/github-hosted-runners).

The workflow syntax, action refs, and upstream compiler commit were checked, but no hosted job has run. A future hosted result is needed to confirm the runner image, dependency downloads, permissions, and artifact upload together. Initial platform support is limited to the executed environments above. Windows, Intel/x86, other distributions, and other compiler revisions remain unverified.

## Fixed-workload measurements

The release command records one sample for `spec/boolean_spec.rb` plus `spec/array_absolute_value_spec.rb`, seed 42, 100 examples per property. These samples include process startup and ran during validation; they are descriptive records, not comparative benchmarks or performance guarantees.

| Environment | Build wall time | Executable bytes | Run wall time |
| --- | ---: | ---: | ---: |
| Local macOS arm64 | 1.396 s | 558,568 | 0.332 s |
| Linux arm64 container | 3.040 s | 630,544 | 0.00152 s |

Raw records: `.agents.local/ci/65195/measurement.json` and `.agents.local/m4/linux-checkout/.agents.local/ci/1/measurement.json`. Whole-run output is in `.agents.local/m4/macos-release.log` and `linux-release.log`. These local artifacts are ignored by Git; CI uploads its own logs and measurements.

The previously documented Spinel scalar-mutation and source-map limitations still apply; see [compiler compatibility](spinel-compatibility.md). This milestone does not repair compiler semantics or expand the MVP generator/target scope.
