require_relative "generators"
require_relative "options"

module Hypo
  VERSION = "0.3.0.dev"

  # Identity is local to a property: assertion, exception class, or passing.
  # Messages are observations, not identities; they may include the input.
  class Evaluation
    attr_reader :identity, :description

    def initialize(identity, description)
      @identity = identity
      @description = description
    end

    def failed?
      !@identity.empty?
    end

    def same_failure?(other)
      failed? && @identity == other.identity
    end
  end

  class Runner
    attr_reader :original_input, :reduced_input, :shrink_evaluations,
                :confirmation_evaluations, :shrink_exhausted, :unstable

    def initialize(args, executable: $0, compiler_version: "unrecorded")
      @executable = executable.include?("/") ? File.expand_path(executable) : executable
      @compiler_version = compiler_version
      @options = Options.new(args)
      @properties = 0
      @names = []
      @selected = 0
      @total_examples = 0
      @passed = 0
      @failures = 0
      @unstable_count = 0
      @executed = 0
      @failed = false
      @active = false
      @assertions = 0
      @original_input = 0
      @reduced_input = 0
      @shrink_evaluations = 0
      @confirmation_evaluations = 0
      @shrink_exhausted = false
      @unstable = false
    end

    def property(name, generator, at:)
      unless name.is_a?(String) && !name.strip.empty?
        raise Error, "property description must be a nonempty string"
      end
      unless generator.is_a?(IntegerGenerator) || generator.is_a?(BooleanGenerator) || generator.is_a?(ArrayGenerator)
        raise Error, "requires an integer, Boolean, or integer-array generator"
      end
      unless at.is_a?(Array) && at.length == 2 && at[0].is_a?(String) && !at[0].empty? && at[1].is_a?(Integer) && at[1] > 0
        raise Error, "property location must be [file, positive line number]"
      end
      raise Error, "duplicate property description: #{name.inspect}" if @names.include?(name)
      @names << name.dup
      @properties += 1
      return unless @options.property.empty? || @options.property == name
      @selected += 1
      @executed = 0
      @failed = false
      @unstable = false
      @shrink_evaluations = 0
      @confirmation_evaluations = 0
      @shrink_exhausted = false
      random = Random.new(@options.seed)
      puts "Hypo #{VERSION} seed=#{@options.seed} examples=#{@options.examples}"
      phase = "generate"
      value = generator.example(random, 0)
      original = Evaluation.new("", "passed")
      best = original
      candidates = []
      index = 0
      loop do
        if phase == "generate"
          @executed += 1
        elsif phase == "shrink"
          @shrink_evaluations += 1
        else
          @confirmation_evaluations += 1
        end
        @assertions = 0
        @active = true
        identity = ""
        description = "passed"
        # All phases invoke the block here, without another forwarding block.
        # Only the user block belongs inside the target-failure rescue boundary.
        input = value.dup
        begin
          yield input
        rescue Error
          raise
        rescue AssertionFailure => error
          identity = "assertion"
          description = "assertion: #{error.message}"
        rescue StandardError => error
          identity = "exception:#{error.class}"
          description = "exception #{error.class}: #{error.message}"
        ensure
          @active = false
        end
        observed = Evaluation.new(identity, description)
        if phase == "generate"
          unless observed.failed?
            break if @executed == @options.examples
            value = generator.example(random, @executed)
            next
          end
          @failed = true
          @original_input = value
          @reduced_input = value
          original = observed
          best = observed
          candidates = generator.shrink_candidates(value, @options.shrink_limit - @shrink_evaluations + 1)
          index = 0
        elsif phase == "shrink"
          if original.same_failure?(observed)
            @reduced_input = value
            best = observed
            candidates = generator.shrink_candidates(value, @options.shrink_limit - @shrink_evaluations + 1)
            index = 0
          else
            index += 1
          end
        else
          @unstable = !best.same_failure?(observed)
          report_failure(name, at, original, best, observed)
          break
        end
        if index < candidates.length && @shrink_evaluations < @options.shrink_limit
          value = candidates[index]
          phase = "shrink"
        else
          @shrink_exhausted = index < candidates.length
          value = @reduced_input
          phase = "confirm"
        end
      end
      @total_examples += @executed
      if @failed
        @failures += 1
        @unstable_count += 1 if @unstable
      else
        @passed += 1
        puts "PASS #{name.inspect} (#{@executed} examples)"
      end
    end

    def report_failure(name, at, original, best, confirmation)
      status = @unstable ? "UNSTABLE" : "FAIL"
      puts "#{status} #{name.inspect} at #{at[0]}:#{at[1]}"
      puts "  original_input=#{@original_input.inspect}"
      puts "  reduced_input=#{@reduced_input.inspect}"
      puts "  original_failure=#{original.description}"
      puts "  failure=#{best.description}"
      puts "  confirmation=#{confirmation.description}"
      puts "  seed=#{@options.seed} example=#{@executed}"
      shrink_status = @shrink_exhausted ? "budget_exhausted" : "complete"
      puts "  shrink_evaluations=#{@shrink_evaluations} shrink_limit=#{@options.shrink_limit} shrink_status=#{shrink_status}"
      puts "  confirmation_evaluations=#{@confirmation_evaluations}"
      puts "  hypo_version=#{VERSION} compiler_version=#{@compiler_version.inspect}"
      puts "  replay: #{shell_quote(@executable)} --seed #{@options.seed} --examples #{@options.examples} --shrink-limit #{@options.shrink_limit} --property #{shell_quote(name)}"
    end

    def shell_quote(value)
      "'" + value.gsub("'") { %q('"'"') } + "'"
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
      raise Error, "no property matches #{@options.property.inspect}" if @selected == 0
      result = @unstable_count > 0 ? "unstable" : (@failures > 0 ? "fail" : "pass")
      puts "RESULT #{result} properties=#{@selected} examples=#{@total_examples} passed=#{@passed} failed=#{@failures} unstable=#{@unstable_count} declared=#{@properties}"
      @failures > 0 ? 1 : 0
    end
  end
end
