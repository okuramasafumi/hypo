# Hypo MVP implementation plan

Status: implementation plan, updated 2026-10-04. M0–M4 implementation is complete; the full local release gate passes on macOS arm64 and Linux arm64 (Debian Bookworm in Docker). The pinned hosted macOS/Ubuntu CI workflow [passed for commit `958270e`](https://github.com/okuramasafumi/hypo/actions/runs/37194069849). Hypo implements integer, Boolean, and integer-array properties, multiple explicit spec files, exact property selection, aggregate results, deterministic generation, bounded shrinking, final failure confirmation, and executable replay. Version 0.4.0 adds help, version metadata, a relocatable native builder package, retained build provenance, and a shared local/CI release command. No release has been published. See [usage and the implemented contract](README.md) and [M0 findings](docs/spinel-compatibility.md).

## Outcome and scope

A developer writes a readable Ruby property with an input generator and assertions, compiles it with Hypo, and runs a native executable. On failure, the executable prints a smaller counterexample and a command that reproduces the failure.

**Confirmed:** specifications use Ruby-like property definitions with generators and assertions; Spinel is the compilation platform; Hypothesis is the product inspiration.

**Planning assumption:** the first test targets are deterministic, terminating functions in local Spinel-compatible Ruby source. CLI programs, HTTP APIs, and arbitrary CRuby applications are outside this MVP. Change this assumption before implementation if a different target is intended.

Hypo itself should compile with Spinel. Building a test executable requires Spinel and its C toolchain; running the resulting executable should require neither Ruby nor Spinel. A native executable is specific to its build platform, not a cross-platform artifact.

The minimum useful loop is **generate → evaluate → shrink → reproduce**. Deliver this before adding a broad generator catalog or integrations.

## Current repository and verified constraints

- At planning time (2026-09-28), the repository had an unborn `main` branch and an untracked scaffold: `spin.toml`, `.gitignore`, `bin/hypo.rb`, and an empty `test/` directory. The entry point prints `Hello from hypo`.
- That scaffold was preserved before implementation. M1 started from clean commit `e3c303f` and recorded incremental transformations under `.agents.local/reviews/m1/`.
- Local Spinel checkout: `/Users/okuramasafumi/src/spinel`, revision `6c97683140c624520836c8f807ba598f0f47a57e`.
- Its compiler reports `spinel 2026.09.12+1457 (6c976831) [apple clang 21.0.0 (cc)]`. Local executables exist under that checkout's `bin/`; `spin` was not found on this session's PATH.
- Spinel compiles Ruby through C into native executables. Its documented AOT constraints rule out depending on runtime `eval`, runtime class generation, or unrestricted reflection. Literal blocks and static calls are the intended design direction, subject to probes.
- `spin test` compares stdout with committed snapshots or CRuby output; nonzero exit also fails. Expected failing Hypo executables therefore need a separate integration harness that checks their output and exit status.
- M0 now verifies the native builder-to-runner chain, repeated literal blocks, three input types, fresh copies, file IO, compiler subprocesses, explicit property locations, and standalone runner execution on macOS arm64. Release backtraces/caller locations are empty. See [the evidence and limits](docs/spinel-compatibility.md); M1 added verified integer generation; M2 now verifies bounded shrinking, final confirmation, and shell-command replay. Additional pinned-compiler limitations concerning captured scalar mutation and source mapping are recorded in the compatibility findings.

## Proposed developer experience

Example `spec/absolute_value_spec.rb`:

```ruby
require_relative "../src/absolute_value"

Hypo.property "absolute value is nonnegative",
              Hypo.integers(min: -1000, max: 1000),
              at: [__FILE__, __LINE__] do |n|
  Hypo.assert(absolute_value(n) >= 0)
end
```

Each property initially requires `at: [__FILE__, __LINE__]` metadata because the tested release compiler provides no automatic caller locations. This identifies the metadata line in the original property file, not an assertion or exception origin.

The generated entry point loads Hypo and configures the runner before loading the specification. This avoids placing setup boilerplate in every spec. `Hypo.assert` requires a Boolean condition and accepts an optional explanatory message. The property description must be nonempty and unique within the suite; it is also the property selector for reproduction.

Build, run, and exact `--property` selection are implemented:

```sh
spin build
./build/bin/hypo build spec/absolute_value_spec.rb -o build/absolute_value_spec
./build/absolute_value_spec --seed 42 --examples 100
./build/absolute_value_spec --property "absolute value is nonnegative" --seed 42 --examples 100
```

`hypo build` takes one or more explicit spec paths, preserving their command-line order; shell expansion handles globs. It generates an entry point with literal `require_relative` references computed from that entry point’s directory and invokes Spinel with `--require-gate`. Absolute `require` references failed the M0 probe. Until broader source-literal emission is verified, reject reference paths requiring backslash escapes (double quotes, backslashes, control characters, or interpolation markers) with a clear build error; spaces and apostrophes passed. There is no custom language parser, runtime spec interpreter, or runtime discovery of property blocks. Treat specifications and target code as trusted Ruby code.

Each property is executed when its top-level declaration is reached. Keep the literal block at that call site and invoke it directly for generation and shrinking; do not require storing heterogeneous closures in a global registry. The final entry-point statement prints the suite summary and sets its exit code. Filtering is applied before executing a property's block, but declarations are still counted and checked for duplicate descriptions.

Build intermediates live in a dedicated directory under `build/`; retain generated Ruby and compiler diagnostics on failure. Pass subprocess arguments as arguments, never as interpolated shell commands. Resolve spec paths before generation and preserve `require_relative` semantics. Publish the requested output only after successful compilation; a failed build must not appear to produce a fresh passing executable.

## MVP behavior contract

### Generators

Start with a deliberately small set:

| Generator | Supported domain | Shrinking direction |
| --- | --- | --- |
| `Hypo.integers(min:, max:)` | Inclusive bounded integers; default -1000..1000 | Toward zero, or the nearest allowed bound if zero is excluded |
| `Hypo.booleans` | `false`, `true` | `true` to `false` |
| `Hypo.arrays(of:, min_size:, max_size:)` | Bounded arrays of integers only; default size 0..20 | Remove chunks, then shrink elements, while respecting bounds |

MVP integer generator bounds are limited to signed 32-bit values, even though the target may use wider integers. Reject inverted bounds, invalid sizes, and unsupported generator combinations before generating cases. Document a hard array-size cap of 1000. These limits keep sampling arithmetic and failure output bounded.

One generated value per property is sufficient initially; an integer array counts as one value. Multi-argument properties, tuples, strings, floats, hashes, arbitrary objects, nested strategies, custom generators, filters/assumptions, and dependent generators are deferred.

M1 freezes a private 32-bit LCG: `state = (1664525 * state + 1013904223) % 4294967296`, initialized directly from the seed. Sampling uses rejection of the incomplete upper interval before modulo mapping; boundary order is valid, unique `min`, `max`, `0`, `-1`, `1`. Boundary cases consume budget but no PRNG draws. Known-answer and rejection-consumption tests pass under CRuby and Spinel. See [the exact contract](README.md#integer-generation-contract).

Begin each property with the same suite seed in an independent PRNG instance. This keeps a selected property's cases unchanged when other properties are added, reordered, or filtered. Correlation between properties is an accepted MVP trade-off. Exercise valid boundary examples first, then sample the remaining budget. Duplicate samples are allowed; count actual executions, not unique values.

### Execution and result semantics

- Default to 100 generation executions per property and a deterministic seed of 0; print both, and allow explicit positive `--examples` and nonnegative bounded `--seed` values. Encourage varying seeds in CI, without claiming random runs prove correctness.
- Count boundary cases within the generation budget. Shrinking and final confirmation have separate counts.
- Stop generation at the first failing example for a property, shrink it, report it, and continue to the next property. Report only one counterexample per property.
- Assertion failures and ordinary exceptions raised by the target are property failures. Framework errors must not be rescued and mislabeled as target failures; keep that rescue boundary immediately around invocation of the property block.
- A suite passes only if at least one selected property actually executed and every selected property passed. Empty suites, unmatched selectors, duplicate descriptions, and invalid options are errors.
- Exit `0` for a passing run/build; `1` for a falsified property or an unstable failure; `2` for usage, configuration, compilation, or framework errors. Preserve the compiler's diagnostics and report its original status when wrapping a compiler failure.
- Target code must terminate and must not deliberately exit the process. Per-case timeouts, process isolation, crashes, and external state recovery are deferred; CI can bound the whole executable externally.

### Shrinking and reproduction

Implement direct value shrinking, not Hypothesis's full search engine or choice-stream model. Use a deterministic candidate order, accept only strictly smaller candidates under a documented ordering, and never leave the generator's domain.

M0 confirmed that the selected release compiler provides no automatic assertion/exception source locations. Apply the planned fallback: permit at most one `Hypo.assert` invocation per property evaluation, rejecting a second as a configuration error. Assertion failure identity is the property identity; exception failure identity is the property identity plus exception class. Reject shrink candidates that change that identity or failure category. Two raise sites of the same exception class can still be conflated; document this limitation and do not claim failure-site preservation. Report the explicitly supplied property location. Multiple assertions with distinct identities and automatic call-site discovery are deferred.

Use at most 1000 candidate evaluations per property. M2 implements `--shrink-limit` with default 1000 and range `0..1000`; the limit is included in replay commands. Report the best counterexample found and whether the budget was exhausted; do not claim it is globally minimal. Re-evaluate that counterexample once more to detect obvious non-reproducibility. If it no longer produces the same failure, report an unstable failure with the original and final observations; never convert it to a pass. This is a check, not a guarantee of determinism.

The failure report includes the property description, explicit property path/line (not the failure origin), original and reduced inputs, assertion/exception details, seed, execution counts, shrink limit status, Hypo/Spinel versions, and a shell-quoted replay command. Seed replay is guaranteed only for the same executable and options with deterministic target behavior. Recompilation, changed specs, compiler upgrades, or generator changes may change the outcome. Persistent counterexample databases and portable replay files are deferred.

For mutable inputs, preserve an untouched copy and give every property evaluation a fresh value, including shrink trials and final confirmation. Never let target mutation corrupt the displayed input or future candidates.

## Implementation structure

Prefer ordinary Ruby files and explicit methods; add abstraction only where the next supported generator requires it.

```text
bin/hypo.rb                 CLI for building spec executables
lib/hypo.rb                 public DSL and suite lifecycle
lib/hypo/build.rb           entry-point emission and Spinel invocation
lib/hypo/random.rb          deterministic private PRNG
lib/hypo/generators.rb      supported domains and candidate production
lib/hypo/runner.rb          case execution, failures, shrinking, counts
lib/hypo/reporter.rb        stable human-readable output and replay command
spec/                      example properties of example target code
examples/                  small passing and intentionally buggy targets
test/                      final unit, snapshot, and integration tests
```

Layout is proposed; confirm `lib/` loading and `spin` conventions in M0. Do not build a plugin registry, generic backend layer, custom Ruby parser, or separate intermediate representation for this MVP. Generated code should visibly call the target and the property block so Spinel can infer types.

## Ordered implementation milestones

| ID | Depends on | Work and independently reviewable decisions | Acceptance gate |
| --- | --- | --- | --- |
| M0 — prove the compilation path (complete) | None | Pin a Spinel revision; probe the literal property block, repeated invocation, generator objects, integer arrays, fresh copies, exception/location reporting, file IO, and argument-vector subprocess launch. Compile a tiny Hypo builder that emits and compiles a runner. Check source loading from a different working directory. | **Passed on macOS arm64**, with the source/location constraints above. A native builder produced a native runner exercising a local function; the runner worked after hiding its sources and removing tools from PATH. Commands, diagnostics, and probe sources are preserved. Linux is not verified. |
| M1 — deliver one integer property end to end (complete) | M0 | Add the proposed property/assert API, private PRNG, integer generator, one-spec build command, generation loop, pass/failure output, seed/options, and exit codes. Specify PRNG arithmetic and candidate ordering. | **Passed on the pinned macOS arm64 toolchain.** Both unit programs pass under CRuby/Spinel; 45 native integration checks cover correct and buggy targets, a known random counterexample, exact repeatability, errors, preserved build outputs, and standalone execution. Runnable correct/buggy examples are included. |
| M2 — shrink and reproduce failures (complete) | M1 | Implement bounded integer shrinking, failure identity, final confirmation, source-aware reporting, and copy/ownership rules. | **Passed on the pinned macOS arm64 toolchain:** 4/4 unit programs match CRuby; 45 M1 regression checks and 19 M2 native checks pass. Threshold failure 100 reduces to 10; positive/negative domains, failure identity, budget exhaustion, and object-state instability are covered. Printed commands reproduce native results, including quoted and moved executable paths. Compiler-specific scalar mutation and source-map limitations are documented. |
| M3 — add Boolean and integer-array properties (complete) | M2 | Add the two remaining generators and shrinkers, multiple explicit spec files, multiple properties, unique descriptions, selection, and aggregated results. Keep these as separate review units when implementing. | **Passed on the pinned macOS arm64 toolchain:** 7/7 unit programs match CRuby; native M1/M2 regressions and M3 mixed-suite integration pass. Both Boolean values, empty/singleton arrays, bounded chunk/element shrinking, mutation-safe confirmation, selected shell replay, aggregate results, and declaration/selection errors are covered. A mutating array target reduces `[10, 10, 10, 10]` to `[3]`. Filtering/reordering files preserves the selected sequence. |
| M4 — make the MVP usable and releasable (complete) | M3 | Finish command help, compiler configuration, retained build artifacts, version metadata, documentation, examples, and pinned CI. Add native end-to-end tests for all exit codes, compiler failure, path quoting, and replay. | **Passed locally on macOS arm64 and Linux arm64:** 7/7 CRuby/native unit programs, 137 native integration checks, all documented runtime examples, and packaging from a clean source copy. A moved package builds through a PATH symlink; its runner replays after package/spec sources and tools are removed. `script/ci.rb` records build time, binary size, and execution time. The pinned hosted macOS and Ubuntu arm64 jobs also passed for commit `958270e`, including compiler build and diagnostic uploads. Initial platform claims are limited to the tested arm64 environments; Windows, x86, and other distributions are unverified. |

Use `SPINEL` as an explicit compiler-path override, then fall back to PATH; document the locally verified path for development. Pin the compiler revision in CI and keep version reporting in failure artifacts. Do not silently use CRuby as the production backend when Spinel fails.

## Validation and completion criteria

Use `spin test` for deterministic unit programs and reviewed snapshots. Use CRuby as a differential reference for supported pure Ruby behavior, with known-answer tests where both backends could share the same bug. A dedicated integration harness should build and launch child executables and assert status/output; intentionally failing children must not make the harness itself fail when their failures are expected.

Before each behavior change, add the narrow regression/contract test and capture its failing result; then implement and rerun the focused tests. Final checked-in tests belong in `test/`. Temporary probes, generated test experiments, logs, and implementation review records belong under `.agents.local/`.

The MVP is complete only when all of these hold:

1. The compiler CLI and generated test runner both run as Spinel-produced executables.
2. Integer, Boolean, and integer-array properties can pass, discover planted failures, and shrink reproducibly within their domains.
3. Failure output names the property and its explicitly supplied source location, shows an honest reduced counterexample, and supplies a verified replay command.
4. Empty suites, invalid options/specs, unavailable compilers, compile errors, target exceptions, and unstable failures never report success.
5. A produced runner works after moving it away from its source tree, with neither Ruby nor Spinel available on PATH.
6. README instructions and the CI definition use the same `ruby script/ci.rb` workflow on the pinned toolchain. That M4 workflow passed locally and in hosted macOS/Ubuntu arm64 CI for commit `958270e`. Subsequent changes require their own validation.

No performance target is a release gate yet. Record build time, binary size, and execution time for a fixed example suite after correctness is established; compare only identical workloads and compiler revisions. Hypothesis feature parity is not an MVP goal.

## Post-MVP steps — M5

1. **Hosted CI: complete.** Both jobs passed for M4 commit `958270e`; the logs confirm all expected checks and uploaded artifacts.
2. **Separate-project trial: implemented and locally validated.** The packaged CLI builds `examples/sorted_ints/` from its own directory. A planted binary-search upper-bound bug reduces from `[-20]` to `[-1]`, replays exactly, and becomes a conventional regression assertion. Repairing the library and rebuilding passes all three properties at three fixed seeds.
3. **Issues from the trial: assessed.** The existing framework API handles the project. The example guide explicitly shows that source repair requires recompilation. The trial adds one unit program and 19 integration checks to the shared release gate; hosted validation of those additions awaits their next push.
4. **Release preparation: next.** Release notes, checksums, and publication remain separate work. No tag or package release has been published.

The trial uses a small library authored for this workflow. Broader third-party adoption and generator expansion are not implied by these results.

## Change recording during implementation

Preserve the uncommitted scaffold before editing. Record each meaningful transformation under `.agents.local/reviews/` with a stable unit ID, explicit dependency IDs, exact incremental patch or snapshot, review question, rationale, invariants, and verification results including checks not run. Keep moves/renames separate from behavior changes when they need separate judgments. Verify that replaying the recorded transformations from the starting state reproduces the final files. Preserve revised versions and keep human acceptance separate; this plan does not record any acceptance or require per-step approval to continue authorized implementation.

## Evidence and design rationale

- [Spinel README](https://github.com/matz/spinel/blob/6c97683140c624520836c8f807ba598f0f47a57e/README.md): compiler pipeline and executable/toolchain model.
- [Spinel limitations](https://github.com/matz/spinel/blob/6c97683140c624520836c8f807ba598f0f47a57e/docs/limitations.md): prefer static source generation and literal blocks to runtime evaluation or reflection.
- [Spin project tooling](https://github.com/matz/spinel/blob/6c97683140c624520836c8f807ba598f0f47a57e/docs/spin.md): project layout, build behavior, and snapshot/CRuby test oracle.
- [Hypothesis execution phases](https://hypothesis.readthedocs.io/en/latest/settings.html) and [flaky failures](https://hypothesis.readthedocs.io/en/latest/tutorial/flaky.html): inspiration for generation, shrinking, and explicit reproducibility limits. The contracts above are Hypo proposals, not claims of Hypothesis compatibility.

Maintainer lens: avoid a second parser and a general-purpose test registry; prove one compiled property before expanding the API. Domain-modeling lens: distinguish a generation budget from a shrink budget, a property failure from a framework error, and a smaller witness from a proven minimum. Their combined recommendation is the staged, narrowly typed API above; M0 verified literal-block compatibility and replaced automatic diagnostic locations with explicit property metadata and the documented weaker failure identity.
