# Hypo

Hypo compiles readable Ruby properties into native test executables with [Spinel](https://github.com/matz/spinel).

**MVP 0.4.0 is implemented:** integer, Boolean, and integer-array properties; multiple spec files; exact selection; deterministic generation; bounded shrinking; failure confirmation; replay; native builder packaging; and a pinned CI workflow. A reported input is a reduced counterexample, not a proven minimum.

## Build and run

Use Spinel revision `6c97683140c624520836c8f807ba598f0f47a57e` and its C toolchain. The full release command passes on macOS arm64 and Linux arm64 (Debian Bookworm in Docker). Other architectures, operating systems, and compiler revisions are outside the initial supported scope. The M4 hosted macOS/Ubuntu workflow [passed for commit `958270e`](https://github.com/okuramasafumi/hypo/actions/runs/37194069849); see [validation evidence and limits](docs/release-validation.md). Put its `bin/` directory on PATH, then run from this checkout:

```sh
spin build
./build/bin/hypo build spec/absolute_value_spec.rb -o build/absolute_value_spec
./build/absolute_value_spec --seed 42 --examples 100
```

To choose the compiler explicitly, set `SPINEL=/path/to/spinel` when invoking `hypo build`. Otherwise it looks for `spinel` on PATH. A checkout-built Hypo builder uses that checkout's runtime source. A packaged builder uses the bundled `lib/` directory, including when invoked through PATH or a symlink. An empty `SPINEL` is an error; it does not fall back to PATH. The produced test executable can be moved and run without that checkout, Ruby, or Spinel; it still requires a compatible OS and architecture.

Both commands provide standalone information options that do not load specs:

```sh
./build/bin/hypo --help
./build/bin/hypo --version
./build/absolute_value_spec --help
./build/absolute_value_spec --version
```

The runner's version output includes the compiler used to build it. `hypo build --help` also shows builder help. Information flags must be used alone.

A spec uses ordinary Ruby and can load a local function with `require_relative`:

```ruby
require_relative "../examples/absolute_value"

Hypo.property "absolute value is nonnegative",
              Hypo.integers(min: -100, max: 100),
              at: [__FILE__, __LINE__] do |number|
  Hypo.assert(absolute_value(number) >= 0)
end
```

`Hypo.property` takes a unique nonempty description, a supported generator, and `at: [file, line]` metadata. Use `at: [__FILE__, __LINE__]`: this Spinel release has no automatic caller locations. The reported location identifies the property metadata line, not the assertion or exception origin.

`Hypo.assert` takes a Boolean condition and an optional String message. False raises a property failure; true passes. At most one assertion may execute per generated example; a second invocation is a configuration error. A property can also fail through an ordinary exception from the target. Specs are trusted code, and targets must terminate without exiting the process.

## Find and repeat a failure

```sh
./build/bin/hypo build spec/buggy_absolute_value_spec.rb -o build/buggy_absolute_value_spec
./build/buggy_absolute_value_spec --seed 42 --examples 100
```

This finds `original_input=100` at `example=2`, reduces it to `reduced_input=10`, confirms that it still fails, and exits 1. The report includes the property location, original and final failure details, separate evaluation counts, Hypo/compiler versions, and a shell-quoted `replay:` command. Run that command with the same executable to repeat a deterministic failure. If invoked by a bare name through PATH, replay requires the same PATH resolution; a path invocation is expanded to an absolute path. Changes to the target, generator, compiler, or executable can change the sequence.

| Exit | Meaning |
| --- | --- |
| 0 | Build succeeded, or every selected property passed its requested example count |
| 1 | An assertion/target exception failed, or final confirmation was unstable |
| 2 | Usage, configuration, compiler, or framework error |

## Suites and property selection

Pass explicit spec files in the desired execution order; the shell can expand globs. Declarations execute in file order, with a new PRNG initialized from the suite seed for each property. Adding, reordering, or filtering unrelated properties preserves a property's input sequence when the target has no shared state.

```sh
./build/bin/hypo build spec/boolean_spec.rb spec/array_absolute_value_spec.rb -o build/suite
./build/suite --seed 42 --examples 100
./build/suite --property "array absolute values are nonnegative" --seed 42 --examples 100
```

`--property` matches the complete, case-sensitive description. Every declaration is validated, including unselected properties; duplicate descriptions are errors. Filtering skips property blocks, but spec files are still loaded and their top-level Ruby executes. Repeated expanded spec paths are rejected at build time. Empty suites and unmatched selectors exit 2.

Each selected property gets its own example and shrink budgets. After a failure, the suite continues with the next property. The final `RESULT` reports selected properties, total generation examples, passed/failed counts, unstable failures (a subset of failed), and declared properties including unselected ones. Any unstable failure makes the suite result `unstable`; otherwise any failure makes it `fail`. Both exit 1. Each replay command selects the reported property explicitly.

Timeouts and a counterexample database remain outside the MVP.

## Integer generation contract

`Hypo.integers(min: -1000, max: 1000)` accepts inclusive integer bounds within `-2147483648..2147483647`. Bounds must be ordered. A singleton range is valid.

The runner accepts `--seed` (default 0, range `0..4294967295`) and `--examples` (default 100, range `1..2147483647`). Values are unsigned decimal strings of at most ten digits. Unknown/duplicate options, missing values, and out-of-range values are errors.

For each property, valid boundary values run first in this order: `min`, `max`, `0`, `-1`, `1`, removing duplicates. They count toward the example budget and do not advance the random state. Subsequent samples can repeat. Generation stops at the first failure.

The initial PRNG algorithm is a 32-bit linear congruential generator:

```text
state starts at seed
state = (1664525 * state + 1013904223) modulo 4294967296
```

For width `max - min + 1`, let `limit = 4294967296 - (4294967296 modulo width)`. Discard draws at or above `limit`, then map the accepted draw to `min + (draw modulo width)`. This removes modulo bias; it does not make successive LCG outputs independent. All intermediate arithmetic fits a signed 64-bit integer. The PRNG state is private to each property and does not use `Kernel.rand`.

## Boolean and array generation

`Hypo.booleans` starts with `false`, then `true`, without consuming random draws. Later values use `random.below(2) == 1`. A failing `true` tries `false`; `false` has no shrink candidates.

`Hypo.arrays(of: Hypo.integers(...), min_size: 0, max_size: 20)` generates integer arrays only. Sizes must be ordered integers in `0..1000`; Boolean elements, nested arrays, and custom generators are unsupported.

Boundary lengths are `min_size`, then 1 if allowed, then `max_size`, removing duplicates. The first boundary array and any singleton contain the minimum element; other boundary arrays contain the maximum element. These arrays consume no random draws. Subsequent arrays sample their length uniformly with the same rejection sampler, then draw each integer from its domain. Empty arrays and equal size/element bounds are valid. Boundary cases count toward the example budget.

Array shrinking first removes chunks: start with `length - min_size`, try consecutive nonoverlapping chunks from left to right, halve the chunk length, and repeat down to one element. It then tries integer reductions at each index from left to right. Accepting a candidate restarts this search. Each candidate strictly reduces either length or, at the same length, the sum of element distances from the integer shrink target. Size and integer bounds are preserved.

Every evaluation receives a fresh array copy, including shrink trials and confirmation. Mutating the argument cannot change the saved original, the reduced input, or future candidates. Shallow copies suffice because only integer elements are supported. Candidate lists retain at most the remaining shrink budget plus one, so large arrays do not materialize every possible element reduction at once.

A mutation-using example with a deliberately buggy scalar target is included:

```sh
./build/bin/hypo build spec/buggy_array_absolute_value_spec.rb -o build/buggy_array
./build/buggy_array --seed 42 --examples 100
```

It reduces an array of twenty `100` values to `[10]`, despite the property mutating its input with `map!`.

## Shrinking and confirmation

The nearest-to-zero value in the generator's domain is the shrink target: zero when allowed, otherwise the closest bound. Candidate order is the target first, followed by values obtained by subtracting half the remaining distance, then a quarter, and so on down to a one-step reduction toward the target. For example, 100 in `-100..100` tries `0, 50, 75, 88, 94, 97, 99`. Each candidate is strictly closer to the target and stays in the domain.

Accept the first candidate with the same failure identity, then restart candidate generation from that value. An assertion cannot be replaced by a target exception, nor one exception class by another. Exception messages can change with the input. Identity is local to the property; this compiler cannot distinguish different raise sites of the same exception class. One assertion per evaluation remains the API limit.

`--shrink-limit` defaults to 1000 and accepts `0..1000`. It bounds candidate evaluations independently of `--examples`; zero skips candidate evaluation. The runner always evaluates the best counterexample once more for confirmation. Reports separate generation, shrink, and confirmation counts. `shrink_status=budget_exhausted` means untried candidates remained when the limit was reached; `complete` means the candidate list was exhausted, not that a global minimum was proved. The replay command includes the shrink limit.

If final confirmation passes or produces a different failure identity, the report says `UNSTABLE`, includes the original, best, and confirmation observations, and still exits 1. Framework/configuration errors in any phase exit 2. One confirmation detects some unstable behavior; it cannot prove that the target is deterministic.

## Build artifacts and current limits

Each build keeps `build-info.txt` (Hypo version, compiler path/version, spec paths, and output), its generated entry point, `compiler-version.log`, and `compiler.log` under a fresh `build/hypo/<id>/` directory in the current working directory. Compilation uses separate process arguments and `--require-gate`. Compiler failures return exit 2 and retain diagnostics and the original subprocess status. Once the artifact directory exists, source-emission and output-preparation errors also report its path. Files for phases not reached may be absent. A successfully compiled executable is renamed into the requested output path; failed builds preserve an existing output. Output must not name a `.rb` file. The output and build directory must be on the same filesystem for that rename.

Generated references are relative to the entry point. Source paths containing spaces and apostrophes are supported. Paths whose Ruby string literals need backslash escapes are rejected, including double quotes, backslashes, control characters, and interpolation markers. This is a measured compiler limitation; see [Spinel compatibility findings](docs/spinel-compatibility.md). The pinned compiler also differs from CRuby for some scalar locals mutated before an exception and some `__LINE__` mappings in larger source files. These observed limits are documented there; Hypo does not repair compiler semantics. The compiled-spec locations and stateful target-object confirmation used in the integration suite are verified.

## Package the native builder

CRuby is needed only for the packaging and test tools below. The packaged builder and its produced test executables run natively.

```sh
SPINEL=/path/to/spinel ruby script/package.rb build/hypo-0.4.0
./build/hypo-0.4.0/bin/hypo --version
./build/hypo-0.4.0/bin/hypo build spec/absolute_value_spec.rb -o build/packaged-example
```

The destination must be new. The package contains `bin/hypo`, its required `lib/` sources, documentation, runnable specs/targets, compiler logs, and `BUILD_INFO` with version/platform metadata. Move or archive the whole directory; keep `bin/` and `lib/` together. Add its `bin/` directory to PATH if desired. Building specs still requires Spinel and its C toolchain. The package is specific to its build OS and architecture, and is not installed globally or published automatically.

Package staging artifacts are retained under `.agents.local/package/`. An existing destination is never overwritten. The generated property executable is independent of the package and source tree once compilation finishes.

## Try Hypo in a separate project

The package includes a [standalone sorted-integer library](examples/sorted_ints/README.md) and three properties. Copy that example to its own directory and follow its guide to plant an exclusive-bound error, reduce the failure to `[-1]`, replay it, and repair/rebuild the target. The library imports no Hypo source; the packaged CLI supplies the framework when compiling its specs.

The automated version is `ruby test/integration/m5_test.rb`. It runs as part of the release checks below and modifies only a disposable project copy.

## Test and release checks

With the pinned `spin` and `spinel` on PATH:

```sh
ruby script/ci.rb
```

For explicit local paths:

```sh
SPINEL=/path/to/spinel SPIN=/path/to/spin ruby script/ci.rb
```

This command checks the compiler revision, runs `spin test` and `spin build`, runs all five native integration harnesses, then builds/runs the documented passing, failing, and selected examples. It checks expected exit codes rather than treating planted failures as harness failures. CRuby is the unit-test reference and subprocess driver. Ruby 3.4.2 is pinned in CI; the local macOS validation also passed with Ruby 4.1.0dev.

For a focused check:

```sh
spin test
SPINEL=/path/to/spinel ruby test/integration/m4_test.rb
```

M1–M3 integration harnesses remain under `test/integration/`. M4 covers help/version before spec loading, compiler overrides and diagnostics, provenance, packaging from a clean source copy, relocation through PATH/symlinks, and standalone replay after hiding package/spec sources and removing tools from PATH. M5 adds a separate consumer project with a binary-search bug, reduced regression, exact replay, source repair, and rebuild.

Logs and a fixed-workload measurement are saved under `.agents.local/ci/<id>/`; integration artifacts live under `.agents.local/m1/` through `.agents.local/m5/`. The measurement records compiler version, host, seed, example count, build time, executable bytes, and execution wall time. It is one descriptive sample with startup overhead, not a performance claim or release threshold.

The [CI workflow](.github/workflows/ci.yml) uses immutable action references and Spinel revision `6c97683140c624520836c8f807ba598f0f47a57e`, builds Spinel with its pinned parser dependencies, and runs the same command on `macos-14` and `ubuntu-24.04-arm`. It retains diagnostics even after a failed check. The hosted runner images themselves receive updates; this is a compiler/source pin, not a bit-for-bit reproducible environment.

See [release validation](docs/release-validation.md) for the successful hosted M4 checks and locally verified M5 additions, and [the MVP plan](MVP_PLAN.md) for the completed scope and deferred features. Implementation patches and validation records are under `.agents.local/reviews/m1/` through `.agents.local/reviews/m5/`.
