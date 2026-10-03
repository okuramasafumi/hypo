# Hypo

Hypo compiles readable Ruby properties into native test executables with [Spinel](https://github.com/matz/spinel).

**M2 is implemented:** one integer property per executable, deterministic generation, bounded shrinking, failure confirmation, and replay commands. A reported input is a reduced counterexample, not a proven minimum. Boolean/array generators and multi-property suites are planned for M3.

## Build and run

Use Spinel revision `6c97683140c624520836c8f807ba598f0f47a57e` and its C toolchain. This revision is the tested baseline on macOS arm64; other revisions and Linux are not yet verified. Put its `bin/` directory on PATH, then run from this checkout:

```sh
spin build
./build/bin/hypo build spec/absolute_value_spec.rb -o build/absolute_value_spec
./build/absolute_value_spec --seed 42 --examples 100
```

To choose the compiler explicitly, set `SPINEL=/path/to/spinel` when invoking `hypo build`. Otherwise it looks for `spinel` on PATH. The Hypo builder currently uses the runtime source from the checkout in which it was compiled. The produced test executable can be moved and run without that checkout, Ruby, or Spinel; it still requires a compatible OS and architecture.

A spec uses ordinary Ruby and can load a local function with `require_relative`:

```ruby
require_relative "../examples/absolute_value"

Hypo.property "absolute value is nonnegative",
              Hypo.integers(min: -100, max: 100),
              at: [__FILE__, __LINE__] do |number|
  Hypo.assert(absolute_value(number) >= 0)
end
```

`Hypo.property` takes a nonempty description, an integer generator, and `at: [file, line]` metadata. Use `at: [__FILE__, __LINE__]`: this Spinel release has no automatic caller locations. The reported location identifies the property metadata line, not the assertion or exception origin.

`Hypo.assert` takes a Boolean condition and an optional String message. False raises a property failure; true passes. At most one assertion may execute per generated example; a second invocation is a configuration error. A property can also fail through an ordinary exception from the target. Specs are trusted code, and targets must terminate without exiting the process.

## Find and repeat a failure

```sh
./build/bin/hypo build spec/buggy_absolute_value_spec.rb -o build/buggy_absolute_value_spec
./build/buggy_absolute_value_spec --seed 42 --examples 100
```

This finds `original_input=100` at `example=2`, reduces it to `reduced_input=10`, confirms that it still fails, and exits 1. The report includes the property location, original and final failure details, separate evaluation counts, Hypo/compiler versions, and a shell-quoted `replay:` command. Run that command with the same executable to repeat a deterministic failure. If invoked by a bare name through PATH, replay requires the same PATH resolution; a path invocation is expanded to an absolute path. Changes to the target, generator, compiler, or executable can change the sequence.

| Exit | Meaning |
| --- | --- |
| 0 | Build succeeded, or the property passed its requested example count |
| 1 | An assertion/target exception failed, or final confirmation was unstable |
| 2 | Usage, configuration, compiler, or framework error |

An empty spec cannot pass. A second property is rejected for now. No property selector, filtering, timeout, or counterexample database is implemented yet.

## Integer generation contract

`Hypo.integers(min: -1000, max: 1000)` accepts inclusive integer bounds within `-2147483648..2147483647`. Bounds must be ordered. A singleton range is valid.

The runner accepts `--seed` (default 0, range `0..4294967295`) and `--examples` (default 100, range `1..2147483647`). Values are unsigned decimal strings of at most ten digits. Unknown/duplicate options, missing values, and out-of-range values are errors.

For each property, valid boundary values run first in this order: `min`, `max`, `0`, `-1`, `1`, removing duplicates. They count toward the example budget and do not advance the random state. Subsequent samples can repeat. Generation stops at the first failure.

The initial PRNG algorithm is a 32-bit linear congruential generator:

```text
state starts at seed
state = (1664525 * state + 1013904223) modulo 4294967296
```

For width `max - min + 1`, let `limit = 4294967296 - (4294967296 modulo width)`. Discard draws at or above `limit`, then map the accepted draw to `min + (draw modulo width)`. This removes modulo bias; it does not make successive LCG outputs independent. All intermediate arithmetic fits a signed 64-bit integer. The PRNG state is private to the run and does not use `Kernel.rand`.

## Shrinking and confirmation

The nearest-to-zero value in the generator's domain is the shrink target: zero when allowed, otherwise the closest bound. Candidate order is the target first, followed by values obtained by subtracting half the remaining distance, then a quarter, and so on down to a one-step reduction toward the target. For example, 100 in `-100..100` tries `0, 50, 75, 88, 94, 97, 99`. Each candidate is strictly closer to the target and stays in the domain.

Accept the first candidate with the same failure identity, then restart candidate generation from that value. An assertion cannot be replaced by a target exception, nor one exception class by another. Exception messages can change with the input. Identity is local to the property; this compiler cannot distinguish different raise sites of the same exception class. One assertion per evaluation remains the API limit.

`--shrink-limit` defaults to 1000 and accepts `0..1000`. It bounds candidate evaluations independently of `--examples`; zero skips candidate evaluation. The runner always evaluates the best counterexample once more for confirmation. Reports separate generation, shrink, and confirmation counts. `shrink_status=budget_exhausted` means untried candidates remained when the limit was reached; `complete` means the candidate list was exhausted, not that a global minimum was proved. The replay command includes the shrink limit.

If final confirmation passes or produces a different failure identity, the report says `UNSTABLE`, includes the original, best, and confirmation observations, and still exits 1. Framework/configuration errors in any phase exit 2. One confirmation detects some unstable behavior; it cannot prove that the target is deterministic.

## Build artifacts and current limits

Each build keeps its generated entry point, `compiler-version.log`, and `compiler.log` under a fresh `build/hypo/<id>/` directory in the current working directory. Compilation uses separate process arguments and `--require-gate`. Compiler failures return exit 2 and retain diagnostics. A successfully compiled executable is renamed into the requested output path; failed builds preserve an existing output. Output must not name a `.rb` file. The output and build directory must be on the same filesystem for that rename.

Generated references are relative to the entry point. Source paths containing spaces and apostrophes are supported. Paths whose Ruby string literals need backslash escapes are rejected, including double quotes, backslashes, control characters, and interpolation markers. This is a measured compiler limitation; see [Spinel compatibility findings](docs/spinel-compatibility.md). The pinned compiler also differs from CRuby for some scalar locals mutated before an exception and some `__LINE__` mappings in larger source files. These observed limits are documented there; Hypo does not repair compiler semantics. The compiled-spec locations and stateful target-object confirmation used in the integration suite are verified.

## Test

```sh
spin test
SPINEL=/path/to/spinel ruby test/integration/m1_test.rb
SPINEL=/path/to/spinel ruby test/integration/m2_test.rb
```

`spin test` runs the generator and runner contract tests under Spinel and compares them with CRuby. The integration harnesses use CRuby to build/run native subprocesses and check their statuses, output, failure preservation, shrinking, confirmation, and exact shell-command replay. Temporary files and logs live under `.agents.local/m1/` and `.agents.local/m2/`.

See [the MVP plan](MVP_PLAN.md) for the remaining milestones. Implementation patches and validation records are under `.agents.local/reviews/m1/` and `.agents.local/reviews/m2/`.
