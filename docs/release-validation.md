# MVP 0.4.0 validation — 2026-10-04

The M4 release gate passed locally and in [hosted CI](https://github.com/okuramasafumi/hypo/actions/runs/37194069849) for commit `958270e3ad53d60ada5486b50135730eb490d87f`. The repository is now published at `okuramasafumi/hypo`; no release tag or package publication was performed by this workflow.

## Executed release gate

`ruby script/ci.rb` passed in both environments, using Spinel source revision `6c97683140c624520836c8f807ba598f0f47a57e`:

| Environment | C compiler | CRuby reference | Result |
| --- | --- | --- | --- |
| macOS 26.6.2, arm64 | Apple clang 21.0.0 | Ruby 4.1.0dev, revision `332315a464` | Passed |
| Debian Bookworm, aarch64, Docker | GCC 12.2.0 | Ruby 3.4.2 | Passed |

Each environment passed seven unit programs compared with CRuby and 137 native integration checks: M1 45, M2 19, M3 47, M4 26. The gate also compiled and ran the documented integer, Boolean/array suite, exact-selector, and deliberately buggy examples, checking pass/failure/error exits explicitly.

The M4 package test copies the source into a clean directory, builds a native package, hides the source directory, moves the package to a path containing spaces and an apostrophe, and invokes its builder through a PATH symlink. After compilation it hides the package and spec sources, removes Ruby/Spinel from PATH, and verifies both the failing runner and its exact printed replay command. The mutation-using array target still reduces to `[3]`.

The Linux compiler was built from an archive of the pinned source and its local vendored parser sources in `ruby:3.4.2-bookworm`. Hypo's release tests then ran with container networking disabled. This exercises Linux arm64; it is not a test of every Linux distribution or an emulated x86 build.

## Hosted M4 validation

`.github/workflows/ci.yml` pins checkout, Ruby setup, and artifact-upload actions by commit, Ruby to 3.4.2, and Spinel to the full revision above. It builds Spinel from source and invokes the same release gate on `macos-14` and `ubuntu-24.04-arm`. Both are arm64 labels in the [GitHub runner reference](https://docs.github.com/en/actions/reference/runners/github-hosted-runners).

[Run 37194069849](https://github.com/okuramasafumi/hypo/actions/runs/37194069849) completed successfully for the exact M4 commit. `native (macos-14)` finished in 1m 57s and `native (ubuntu-24.04-arm)` in 4m 36s. Each job built the pinned compiler, passed seven unit programs and all 137 native integration checks, ran the documented examples, and uploaded diagnostics. Hosted logs were inspected to confirm the checks actually executed.

This extends the tested environments to the hosted macOS 14 and Ubuntu 24.04 arm64 images. Windows, Intel/x86, other distributions, and other compiler revisions remain unverified. The later M5 additions below are not part of this hosted result.

## Fixed-workload measurements

The release command records one sample for `spec/boolean_spec.rb` plus `spec/array_absolute_value_spec.rb`, seed 42, 100 examples per property. These samples include process startup and ran during validation; they are descriptive records, not comparative benchmarks or performance guarantees.

| Environment | Build wall time | Executable bytes | Run wall time |
| --- | ---: | ---: | ---: |
| Local macOS arm64 | 1.396 s | 558,568 | 0.332 s |
| Linux arm64 container | 3.040 s | 630,544 | 0.00152 s |

Raw records: `.agents.local/ci/65195/measurement.json` and `.agents.local/m4/linux-checkout/.agents.local/ci/1/measurement.json`. Whole-run output is in `.agents.local/m4/macos-release.log` and `linux-release.log`. These local artifacts are ignored by Git; CI uploads its own logs and measurements.

The previously documented Spinel scalar-mutation and source-map limitations still apply; see [compiler compatibility](spinel-compatibility.md). This milestone does not repair compiler semantics or expand the MVP generator/target scope.

## M5 consumer trial

A new standalone reference project, `examples/sorted_ints/`, exercises binary-search insertion positions and nonmutating sorted insertion. It is copied from the native package and run from a separate working directory, without importing Hypo's checkout sources. This is an authored consumer example, not a claim that Hypo has been adopted by a third-party production library.

The trial deliberately changes the search's exclusive upper bound from `numbers.length` to `numbers.length - 1`. Hypo finds `[-20]`, reduces it to `[-1]`, and prints an exact selected replay command. An ordinary regression assertion fails against the buggy source and passes after repair. The old native executable keeps failing until rebuilt; the rebuilt library passes all three properties at seeds 0, 42, and 4294967295.

The M5 integration harness adds 19 checks, and the library's independent contract program brings the unit total to eight. The expanded release gate is locally validated on macOS arm64 and Linux arm64 (Debian Bookworm container); hosted validation of these additions awaits their next push. Evidence is retained under `.agents.local/m5/`, including correct/buggy source snapshots and the failure report. Hypo's existing runtime and generator API handled this trial without implementation changes.
