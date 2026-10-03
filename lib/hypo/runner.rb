require_relative "generators"
require_relative "options"

module Hypo
  class Runner
    def initialize(args)
      @options = Options.new(args)
      @properties = 0
      @executed = 0
      @failed = false
      @active = false
      @assertions = 0
    end

    def property(name, generator, at:)
      raise Error, "M1 supports one property per executable" unless @properties == 0
      unless name.is_a?(String) && !name.strip.empty?
        raise Error, "property description must be a nonempty string"
      end
      unless generator.is_a?(IntegerGenerator)
        raise Error, "M1 requires an integer generator"
      end
      unless at.is_a?(Array) && at.length == 2 && at[0].is_a?(String) && !at[0].empty? && at[1].is_a?(Integer) && at[1] > 0
        raise Error, "property location must be [file, positive line number]"
      end
      @properties += 1
      random = Random.new(@options.seed)
      puts "Hypo M1 seed=#{@options.seed} examples=#{@options.examples}"
      while @executed < @options.examples
        value = generator.example(random, @executed)
        @executed += 1
        @assertions = 0
        @active = true
        failure = ""
        # Only the user block belongs inside the target-failure rescue boundary.
        begin
          yield value
        rescue Error
          raise
        rescue AssertionFailure => error
          failure = "assertion: #{error.message}"
        rescue StandardError => error
          failure = "exception #{error.class}: #{error.message}"
        ensure
          @active = false
        end
        unless failure.empty?
          @failed = true
          puts "FAIL #{name.inspect} at #{at[0]}:#{at[1]}"
          puts "  input=#{value}"
          puts "  #{failure}"
          puts "  seed=#{@options.seed} example=#{@executed}"
          break
        end
      end
      puts "PASS #{name.inspect} (#{@executed} examples)" unless @failed
    end

    def assert(condition, message)
      raise Error, "assert must be called inside a property" unless @active
      @assertions += 1
      raise Error, "only one assertion is allowed per property evaluation" if @assertions > 1
      unless condition.is_a?(TrueClass) || condition.is_a?(FalseClass)
        raise Error, "assert requires a Boolean condition"
      end
      raise Error, "assert message must be a string" unless message.is_a?(String)
      raise AssertionFailure, message unless condition
    end

    def finish
      raise Error, "no properties executed" if @properties == 0
      result = @failed ? "fail" : "pass"
      puts "RESULT #{result} properties=#{@properties} examples=#{@executed}"
      @failed ? 1 : 0
    end
  end
end
