require_relative "../lib/hypo/generators"

def check(condition, message)
  raise message unless condition
end

generator = Hypo.integers(min: -100, max: 100)
check(generator.shrink_candidates(100) == [0, 50, 75, 88, 94, 97, 99], "positive candidate order")
check(generator.shrink_candidates(-100) == [0, -50, -75, -88, -94, -97, -99], "negative candidate order")
check(generator.shrink_candidates(0) == [], "zero is terminal")
check(Hypo.integers(min: 7, max: 7).shrink_candidates(7) == [], "singleton is terminal")
check(Hypo.integers(min: 5, max: 100).shrink_candidates(100) == [5, 53, 77, 89, 95, 98, 99], "positive-only domain")
check(Hypo.integers(min: -100, max: -5).shrink_candidates(-100) == [-5, -53, -77, -89, -95, -98, -99], "negative-only domain")

# Exhaust small domains: every candidate stays valid and strictly closer to the
# domain's nearest-to-zero value; no repetition can cycle a search.
(-6..6).each do |minimum|
  (minimum..6).each do |maximum|
    domain = Hypo.integers(min: minimum, max: maximum)
    pivot = minimum > 0 ? minimum : (maximum < 0 ? maximum : 0)
    (minimum..maximum).each do |value|
      candidates = domain.shrink_candidates(value)
      seen = []
      candidates.each do |candidate|
        check(candidate >= minimum && candidate <= maximum, "candidate in domain")
        check((candidate - pivot).abs < (value - pivot).abs, "strict reduction")
        check(!seen.include?(candidate), "unique candidates")
        seen << candidate
      end
    end
  end
end
wide = Hypo.integers(min: -2147483648, max: 2147483647)
check(wide.shrink_candidates(-2147483648).last == -2147483647, "minimum integer neighbor")
check(wide.shrink_candidates(2147483647).last == 2147483646, "maximum integer neighbor")
check(wide.shrink_candidates(-2147483648).length == 32, "bounded candidate list")
puts "integer shrinking candidates: passed"
