# M0: Spinel compatibility findings

Verified on 2026-09-30 on macOS arm64. M0 is complete with the implementation constraints below. M1 has not started; the runtime and builder used here are compatibility probes, not a released Hypo API.

## Toolchain baseline

Use Spinel revision `6c97683140c624520836c8f807ba598f0f47a57e` as the initial implementation baseline. The tested executable reports:

```text
spinel 2026.09.12+1457 (6c976831) [apple clang 21.0.0 (cc)]
```

The compiler and project tool are `/Users/okuramasafumi/src/spinel/bin/spinel` and `/Users/okuramasafumi/src/spinel/bin/spin`. They are not on this shell's PATH. CRuby comparison used `ruby 4.1.0dev (2026-05-20T10:44:12Z master 332315a464) +PRISM [arm64-darwin24]`.

This is the tested revision, not a claim about newer Spinel builds. Repeat these probes before changing it. CI enforcement of the compiler revision belongs to M4.

## Results

| Capability | Observed result | Implementation consequence |
| --- | --- | --- |
| A literal block passed to a module method and yielded repeatedly | Three evaluations at each of five property call sites matched CRuby output | Execute properties directly at their declaration; no closure registry is necessary |
| Different generator objects at different call sites | Integer, Boolean, and integer-array values all worked through the same property method | The proposed one-generator API is viable on this compiler |
| Keyword arguments and explicit location pairs | `min:`, `max:`, and `at: [__FILE__, __LINE__]` compiled; the original file and line survived `require_relative` | Pass property location explicitly |
| Copies before calling the block | `dup` worked for all three input types; array changes inside the property did not change its saved original | Preserve an original input and pass a copy for each evaluation |
| Exception boundaries | Custom assertion errors and `ArgumentError` were rescued distinctly, with correct class and message | The basic failure boundary is viable; full result classification remains M1 work |
| Automatic source locations in the release build | `caller`, `caller_locations`, and rescued exception `backtrace` returned `[]` | Do not promise automatic assertion/exception source locations |
| Integer arithmetic | Five Park–Miller recurrence values, its maximum-state multiplication/modulo case, a 2^32 domain width, and negative integer division matched known answers and CRuby | There is a bounded-arithmetic PRNG option; algorithm selection and unbiased domain sampling remain M1 work |
| File IO and path calculations | `File.write`, `File.read`, `Pathname#relative_path_from`, and `File.rename` worked in a native builder | Emit source relative to the generated entry point, then publish a successfully compiled output |
| Compiler launch and status | `Process.spawn` with separate arguments and `Process.waitpid2` worked; nonzero and missing compiler cases returned builder exit 2 | Preserve compiler diagnostics/status and avoid shell command interpolation |
| Complete native build chain | Spinel compiled the builder; that builder emitted Ruby and invoked Spinel to compile a runner exercising a local function | No CRuby production backend is needed |
| Source loading from another working directory | Generated relative references and the spec's own `require_relative` worked; spaces and apostrophes in paths worked | Calculate references from the entry point's directory, not the launch directory |
| Standalone execution | A copied runner matched CRuby output after hiding the source directory and setting PATH to an empty directory | The tested runner does not need source files, Ruby, or Spinel at execution time |
| `spin build` with a `lib/` directory | An isolated scaffold built and ran a `bin/` entry point requiring `../lib/hypo` and a spec | Explicit relative loading works with the project tool |

## Decisions for M1

### Property locations and failure identity

Use the explicit property location in the initial API:

```ruby
Hypo.property "absolute value is nonnegative",
              Hypo.integers(min: -1000, max: 1000),
              at: [__FILE__, __LINE__] do |number|
  Hypo.assert(absolute_value(number) >= 0)
end
```

The location identifies the property declaration's metadata line; it is not the assertion line or the target's exception origin. Require this metadata initially and validate its shape. Do not infer the caller using a default argument containing `__FILE__` or `__LINE__`; that would name the library definition.

Apply the fallback already allowed by the MVP plan: at most one `Hypo.assert` per evaluation of a property. Reject a second assertion invocation as a configuration error. For shrinking, assertion identity is the property identity; exception identity is the property identity plus exception class. A change from an assertion failure to a target exception is not an acceptable reduction.

This weaker exception identity can accept a failure from a different raise site of the same class. State that limitation in the report/documentation; do not claim failure-site preservation. Multiple assertions with distinct identities and automatic call-site discovery are deferred. The probe validates the metadata transport, not the future assertion-count enforcement or shrink algorithm.

### Source generation

Emit literal `require_relative` references computed relative to the generated entry point. The first builder used absolute `require` references, which CRuby loaded but this Spinel build rejected with `cannot load such file`. Changing to relative references made the native build chain pass. Keep `--require-gate` enabled.

One additional edge case remains unsupported: when a source directory contains the literal characters `#{literal}`, `String#dump` produces a `\#{literal}` escape. The compiler's `require_relative` resolution treated that backslash as part of the filename and failed. Ordinary spaces and apostrophes were tested successfully. Until a broader literal-emission strategy is verified, M1 should reject generated reference paths requiring backslash escapes (including double quotes, backslashes, control characters, and interpolation markers) with a clear build error. Do not silently sanitize paths or reinterpret Ruby specifications.

The prototype compiles to a sibling `.pending` output and renames it only on success. Its failing and missing compiler tests preserved an existing output file. Production handling of unique temporary paths, cleanup, concurrency, and all IO errors is not established by this prototype.

## Evidence and reproduction

All experimental source, executables, scripts, and logs are under `.agents.local/m0/`. The implementation review records preserve their source/log snapshots under `.agents.local/reviews/m0/`.

- `probes/runtime.rb`, `probes/spec.rb`, `probes/subject.rb`, `probes/entry.rb`: final property API shape, distinct input types, failure boundaries, and mutation checks.
- `probes/locations.rb`: release-build empty backtraces/caller information.
- `probes/explicit_location_entry.rb`: explicit location through a required file.
- `probes/arithmetic.rb`: candidate PRNG arithmetic with known expected values.
- `probes/builder.rb`: native builder prototype; `builder-v1.rb` preserves the failed absolute-require version.
- `logs/entry.json`, `logs/locations.json`, `logs/explicit_location_entry.json`, `logs/arithmetic.json`: actual commands, exit statuses, stdout, and stderr.
- `logs/build-check.json`: native build, CRuby comparison, moved standalone runner, compiler failure, and missing compiler.
- `logs/build-check-absolute-require-failure.json` and `logs/escaped-relative-path.json`: retained compiler failures.
- `logs/spin-project.json`: isolated `spin build` and execution evidence.

From the repository root, the saved artifacts can be rerun with:

```sh
python3 .agents.local/m0/run_probe.py entry
python3 .agents.local/m0/run_probe.py locations
python3 .agents.local/m0/run_probe.py explicit_location_entry
python3 .agents.local/m0/run_probe.py arithmetic
/Users/okuramasafumi/src/spinel/bin/spinel \
  .agents.local/m0/probes/builder.rb --require-gate \
  -o .agents.local/m0/builder
python3 .agents.local/m0/check_build.py
python3 .agents.local/m0/verify_results.py
```

Python and CRuby are verification tools here, not dependencies of the generated runner. The build-check script uses disposable artifacts under `.agents.local/m0/build-check/`, including replacing its own output with a sentinel to check failed-build preservation; its successful standalone runner remains under `build-check/elsewhere/portable-runner`.

## Validation limits

Not verified: Linux, full CLI parsing, production suite state, generator coverage/distribution, actual shrinking, seed replay, all user errors, signals/timeouts, cross compilation, or packaging. No speed or portability claim beyond the tested environment follows from M0. The next step is M1: one integer property, deterministic generation, and truthful pass/failure behavior end to end.


## M2 follow-up (2026-10-04)

The same pinned compiler passes bounded integer shrinking, failure-class preservation, object-state-based unstable-failure detection, and executable replay tests. Public-API fixtures report their expected original spec locations. M2 deliberately reports failure identity by property and exception class, without claiming automatic raise-site identity.

Two additional compiler differences were observed during M2 and remain outside Hypo's implementation:

- A captured scalar local incremented inside a property before an assertion exception did not retain its update across evaluations in the native probe. CRuby advanced from 1 to 2; native execution printed 1 twice. Moving to a single invocation site and removing an intermediate forwarding block did not resolve it. The emitted C places the local update inside a `setjmp` rescue boundary; that is evidence for investigation, not a verified compiler fix. The unstable-failure acceptance tests use a target object with instance state, which does retain updates under both runtimes and correctly triggers `UNSTABLE`. See `.agents.local/m2/probes/mutation.rb` and `logs/mutation-three-sites.json`.
- In the larger direct-runner unit program, `__LINE__` was two lines higher in native output than in CRuby. Moving the evaluation-result class into the runner file did not resolve it. Those algorithm tests now pass fixed source metadata to isolate their contract. Separate native integration tests verify the actual `__FILE__`/`__LINE__` values in compiled public-API specs; their locations match. Do not generalize that coverage into a guarantee about all compiler source mappings. The unmodified discrepancy is retained in `.agents.local/m2/logs/shrinking-target.json` and `logs/shrinking-inline-result.json`.

Intermediate sources and failing probe logs are retained under `.agents.local/m2/`; the final implementation and its passing verification are recorded under `.agents.local/reviews/m2/`. These are compiler compatibility limits, not evidence that shrinking or confirmation passed before the corrected acceptance tests ran.

## M3 follow-up (2026-10-04)

The pinned compiler now passes mixed suites of integer, Boolean, and integer-array properties through the native builder. The seven unit programs match CRuby. Native integration verifies per-property generation and shrink budgets, aggregate failures (including an unstable failure followed by a pass), exact selection, duplicate descriptions across files and unselected declarations, ordered explicit spec loading, and shell-quoted replay of a property name containing shell metacharacters. Reordering/filtering unrelated spec files preserves the selected array sequence.

The array acceptance target clears its argument on every evaluation. The report still preserves `[10, 10, 10, 10]`, reduces it to `[3]`, and confirms the failure with a fresh array. Boundary arrays do not advance the PRNG, including when the element domain contains only one integer. These are implemented runtime checks, extending M0's earlier copy/type probes.

The source-map discrepancy noted in M2 also appeared in `runner_test.rb` after adding array support; that algorithm test now uses fixed locations. Native M3 public-API fixtures separately verify their actual integer/Boolean/array declaration lines. Existing compiler limitations and the unverified Linux/packaging scope remain. M3 logs and exact implementation records live under `.agents.local/m3/` and `.agents.local/reviews/m3/`.

## M4 follow-up (2026-10-04)

The full release gate now passes with the pinned compiler on macOS arm64 and Debian Bookworm arm64 in Docker. Native package relocation uses `File.realpath` and PATH lookup to locate the bundled runtime source; a package compiled from a clean source copy builds a runner after that source copy is hidden. Help/version handling occurs before spec loading. Both platforms pass seven CRuby/native unit programs and 137 native integration checks, including standalone replay without package/spec sources or development tools.

The existing compiler limitations remain. The configured hosted macOS/Ubuntu workflow has not run, and x86/Windows are unverified. See [release validation and exact boundaries](release-validation.md); records are under `.agents.local/m4/` and `.agents.local/reviews/m4/`.
