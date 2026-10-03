class UnstableTarget
  def initialize
    @calls = 0
  end

  def passes?
    @calls += 1
    @calls > 1
  end
end

target = UnstableTarget.new
Hypo.property "unstable", Hypo.integers(min: 10, max: 10), at: [__FILE__, __LINE__] do |value|
  Hypo.assert(target.passes?, "first evaluation fails")
end
