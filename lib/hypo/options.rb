require_relative "errors"

module Hypo
  class Options
    attr_reader :seed, :examples, :shrink_limit, :property

    def initialize(args)
      @property = ""
      @seed = 0
      @examples = 100
      @shrink_limit = 1000
      seen = []
      index = 0
      while index < args.length
        option = args[index]
        unless option == "--seed" || option == "--examples" || option == "--shrink-limit" || option == "--property"
          raise Error, "unknown runner option: #{option}"
        end
        raise Error, "duplicate option: #{option}" if seen.include?(option)
        seen << option
        raise Error, "missing value for #{option}" if index + 1 >= args.length
        value = args[index + 1]
        if option == "--property"
          raise Error, "property selector must be nonempty" if value.strip.empty?
          @property = value
          index += 2
          next
        end
        unless value.length <= 10 && value.match?(/\A[0-9]+\z/)
          raise Error, "#{option} requires an unsigned decimal integer (at most 10 digits)"
        end
        number = value.to_i
        if option == "--seed"
          raise Error, "seed must be in 0..4294967295" if number > 4294967295
          @seed = number
        elsif option == "--shrink-limit"
          raise Error, "shrink limit must be in 0..1000" if number > 1000
          @shrink_limit = number
        else
          unless number >= 1 && number <= 2147483647
            raise Error, "examples must be in 1..2147483647"
          end
          @examples = number
        end
        index += 2
      end
    end
  end
end
