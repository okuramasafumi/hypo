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
      @width = max - min + 1
      @boundaries = [min]
      [max, 0, -1, 1].each do |value|
        if value >= min && value <= max && !@boundaries.include?(value)
          @boundaries << value
        end
      end
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
