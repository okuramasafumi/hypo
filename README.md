# Hypo

Hypo compiles readable Ruby properties into native test executables with [Spinel](https://github.com/matz/spinel).

**M1 is implemented:** one integer property per executable, deterministic generation, and counterexample reporting. Shrinking is next; a reported input is the first failure found, not a minimal counterexample. Boolean/array generators and multi-property suites are planned later.

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

This reports `input=100`, `seed=42`, and `example=2`, then exits 1. Running the same executable with the same options repeats the failure for a deterministic target. Keep the executable and options when reproducing an issue; changes to the target, generator, or toolchain can change the sequence.

| Exit | Meaning |
| --- | --- |
| 0 | Build succeeded, or the property passed its requested example count |
| 1 | An assertion failed or the target raised an ordinary exception |
| 2 | Usage, configuration, compiler, or framework error |

An empty spec cannot pass. A second property is rejected in M1. No property selector, filtering, timeout, shrinking, or counterexample database is implemented yet.

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

## Build artifacts and current limits

Each build keeps its generated entry point and `compiler.log` under a fresh `build/hypo/<id>/` directory in the current working directory. Compilation uses separate process arguments and `--require-gate`. Compiler failures return exit 2 and retain diagnostics. A successfully compiled executable is renamed into the requested output path; failed builds preserve an existing output. Output must not name a `.rb` file. The output and build directory must be on the same filesystem for that rename.

Generated references are relative to the entry point. Source paths containing spaces and apostrophes are supported. Paths whose Ruby string literals need backslash escapes are rejected, including double quotes, backslashes, control characters, and interpolation markers. This is a measured compiler limitation; see [M0 findings](docs/spinel-compatibility.md).

## Test

```sh
spin test
SPINEL=/path/to/spinel ruby test/integration/m1_test.rb
```

`spin test` runs the generator and runner contract tests under Spinel and compares them with CRuby. The integration harness uses CRuby to build/run native subprocesses and check their statuses, output, failure preservation, and repeatability. Its temporary files and logs live under `.agents.local/m1/`.

See [the MVP plan](MVP_PLAN.md) for the remaining milestones. Implementation patches and validation records are under `.agents.local/reviews/m1/`.
