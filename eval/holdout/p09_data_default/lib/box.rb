Box = Data.define(:width, :height, :depth) do
  def volume
    width * height * depth
  end

  def fits_in?(other)
    width <= other.width && height <= other.height && depth <= other.depth
  end

  def cube?
    width == height && height == depth
  end
end
