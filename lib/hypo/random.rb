require_relative "errors"

module Hypo
  # Private, versioned sequence: a full-period 32-bit LCG. Arithmetic fits int64.
  # State is independent of Kernel.rand and the tested program's random state.
  class Random
    def initialize(seed)
      unless seed.is_a?(Integer) && seed >= 0 && seed <= 4294967295
        raise Error, "seed must be an integer in 0..4294967295"
      end
      @state = seed
    end

    def next_u32
      @state = (1664525 * @state + 1013904223) % 4294967296
    end

    # Reject the incomplete interval instead of introducing modulo bias.
    def below(width)
      unless width.is_a?(Integer) && width >= 1 && width <= 4294967296
        raise Error, "random width must be an integer in 1..4294967296"
      end
      limit = 4294967296 - (4294967296 % width)
      value = next_u32
      while value >= limit
        value = next_u32
      end
      value % width
    end
  end
end
