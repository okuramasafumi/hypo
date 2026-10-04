# A separate-project trial with Hypo

This is a small reference library written for the Hypo consumer trial. It finds insertion positions in sorted integer arrays and inserts values without changing the input. It has no dependency on Hypo; only the property files use Hypo's API. This is a practical workflow example, not a compatibility claim about an existing third-party library.

Copy this directory out of a Hypo package, put the package's `bin/` on PATH, and select the pinned compiler:

```sh
cp -R /path/to/hypo-package/examples/sorted_ints /path/to/my-sorted-ints
cd /path/to/my-sorted-ints
export PATH="/path/to/hypo-package/bin:$PATH"
export SPINEL=/path/to/spinel
hypo build spec/partition_spec.rb spec/insertion_spec.rb -o build/properties
./build/properties --seed 42 --examples 100
```

Use a new copy destination. The example and package paths are placeholders for your local directories. The produced runner does not need Hypo, Ruby, or Spinel to execute.

The suite checks three contracts:

- The insertion position for zero follows every negative element. A linear count is the reference for the binary search.
- Binary search handles varying keys against a fixed array containing duplicate zeros.
- Inserting zero preserves ordering, duplicates, and the original input. Sorting a new array is the independent reference.

The expected summary is `RESULT pass properties=3 examples=300`. Each property executes 100 generated inputs. The target expects already-sorted arrays; the specs sort generated inputs before calling it.

## Find, shrink, replay, fix

In your copied `lib/sorted_ints.rb`, change this line:

```ruby
high = numbers.length
```

to this deliberate bug:

```ruby
high = numbers.length - 1
```

The search uses an exclusive upper bound, so subtracting one removes the final insertion position. Rebuild and run the same commands. All three properties fail. To concentrate on the array counterexample:

```sh
./build/properties --property "lower_bound partitions at zero" --seed 42 --examples 100
```

Hypo reports `original_input=[-20]`, `reduced_input=[-1]`, and the location of the property in `spec/partition_spec.rb`. For `[-1]` and key 0, the faulty implementation returns 0; the correct insertion position is 1. Run the report's shell-quoted `replay:` command to reproduce the same selected failure.

You can preserve the reduced case as an ordinary regression test:

```ruby
require_relative "lib/sorted_ints"
raise "wrong insertion position" unless SortedInts.lower_bound([-1], 0) == 1
```

Restore the exclusive bound to `numbers.length`, rebuild, and run again. The three properties pass. Editing source alone does not change an already-compiled runner; replay uses the executable currently at the reported path.

## Automated trial

From the Hypo source checkout:

```sh
SPINEL=/path/to/spinel ruby test/integration/m5_test.rb
```

The harness packages Hypo, copies this project from the package, builds and runs it from its own directory, introduces the bug only in the copy, verifies shrinking and exact replay, runs the reduced regression before and after repair, and rebuilds. The repaired library passes seeds 0, 42, and 4294967295. Source snapshots, the failure report, and subprocess logs remain under `.agents.local/m5/` in the Hypo checkout.
