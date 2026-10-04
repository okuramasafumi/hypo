require_relative "random"

module Hypo
  class IntegerGenerator
    attr_reader :min, :max

    def initialize(min, max)
      unless min.is_a?(Integer) && max.is_a?(Integer)
        raise Error, "integer bounds must be integers"
      end
      unless min >= -2147483648 && max <= 2147483647 && min <= max
        raise Error, "integer bounds must be ordered within -2147483648..2147483647"
      end
      @min = min
      @max = max
      @pivot = min > 0 ? min : (max < 0 ? max : 0)
      @width = max - min + 1
      @boundaries = [min]
      [max, 0, -1, 1].each do |value|
        if value >= min && value <= max && !@boundaries.include?(value)
          @boundaries << value
        end
      end
    end

    def draw(random)
      @min + random.below(@width)
    end

    # Try the nearest-to-zero value, then increasingly small steps toward it.
    # Distance to @pivot strictly decreases, including when zero is excluded.
    def shrink_candidates(value, limit = 1001)
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
        draw(random)
      end
    end
  end

  def self.integers(min: -1000, max: 1000)
    IntegerGenerator.new(min, max)
  end
end

module Hypo
  class BooleanGenerator
    def example(random, index)
      return false if index == 0
      return true if index == 1
      random.below(2) == 1
    end

    def shrink_candidates(value, limit = 1001)
      value ? [false] : []
    end
  end

  def self.booleans
    BooleanGenerator.new
  end
end

module Hypo
  class ArrayGenerator
    def initialize(of, min_size, max_size)
      raise Error, "arrays require an integer element generator" unless of.is_a?(IntegerGenerator)
      unless min_size.is_a?(Integer) && max_size.is_a?(Integer) && min_size >= 0 && min_size <= max_size && max_size <= 1000
        raise Error, "array sizes must be ordered integers within 0..1000"
      end
      @of = of
      @min_size = min_size
      @max_size = max_size
      @sizes = [min_size]
      @sizes << 1 if min_size <= 1 && max_size >= 1 && !@sizes.include?(1)
      @sizes << max_size unless @sizes.include?(max_size)
    end

    def example(random, index)
      values = []
      if index < @sizes.length
        size = @sizes[index]
        element = index == 0 || size == 1 ? @of.min : @of.max
        while values.length < size
          values << element
        end
      else
        size = @min_size + random.below(@max_size - @min_size + 1)
        while values.length < size
          values << @of.draw(random)
        end
      end
      values
    end

    # Retain at most the remaining evaluation budget plus one candidate. The
    # extra candidate tells the runner whether the budget left work untried.
    def shrink_candidates(value, limit = 1001)
      candidates = []
      chunk = value.length - @min_size
      while chunk > 0
        start = 0
        while start + chunk <= value.length
          candidate = value.dup
          candidate.slice!(start, chunk)
          candidates << candidate
          return candidates if candidates.length >= limit
          start += chunk
        end
        chunk /= 2
      end
      value.each_with_index do |element, index|
        @of.shrink_candidates(element).each do |smaller|
          candidate = value.dup
          candidate[index] = smaller
          candidates << candidate
          return candidates if candidates.length >= limit
        end
      end
      candidates
    end
  end

  def self.arrays(of:, min_size: 0, max_size: 20)
    ArrayGenerator.new(of, min_size, max_size)
  end
end
