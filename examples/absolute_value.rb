def absolute_value(number)
  number < 0 ? -number : number
end

# Deliberate bug for demonstrating a counterexample.
def buggy_absolute_value(number)
  number > 9 ? -number : absolute_value(number)
end
