# A small standalone library. Inputs must be arrays sorted in ascending order.
module SortedInts
  # First position whose element is >= key, or numbers.length if none exists.
  def self.lower_bound(numbers, key)
    low = 0
    high = numbers.length
    while low < high
      middle = low + (high - low) / 2
      if numbers[middle] < key
        low = middle + 1
      else
        high = middle
      end
    end
    low
  end

  # Return a new sorted array, inserting before any existing equal elements.
  def self.insert(numbers, key)
    result = numbers.dup
    result.insert(lower_bound(numbers, key), key)
    result
  end
end
