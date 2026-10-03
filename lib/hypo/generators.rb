require_relative "random"

module Hypo
  class IntegerGenerator
    def initialize(min, max)
      unless min.is_a?(Integer) && max.is_a?(Integer)
        raise Error, "integer bounds must be integers"
      end
      unless min >= -2147483648 && max <= 2147483647 && min <= max
        raise Error, "integer bounds must be ordered within -2147483648..2147483647"
      end
      @min = min
      @pivot = min > 0 ? min : (max < 0 ? max : 0)
      @width = max - min + 1
      @boundaries = [min]
      [max, 0, -1, 1].each do |value|
        if value >= min && value <= max && !@boundaries.include?(value)
          @boundaries << value
        end
      end
    end

    # Try the nearest-to-zero value, then increasingly small steps toward it.
    # Distance to @pivot strictly decreases, including when zero is excluded.
    def shrink_candidates(value)
      return [] if value == @pivot
      candidates = [@pivot]
      direction = value > @pivot ? 1 : -1
      step = (value - @pivot).abs / 2
      while step > 0
        candidates << value - direction * step
        step /= 2
      end
      candidates
    end

    def example(random, index)
      if index < @boundaries.length
        @boundaries[index]
      else
        @min + random.below(@width)
      end
    end
  end

  def self.integers(min: -1000, max: 1000)
    IntegerGenerator.new(min, max)
  end
end
