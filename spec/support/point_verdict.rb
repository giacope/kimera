# frozen_string_literal: true

# What a mutation point's marks say, read the way the specs ask for it: whether
# it is safe, the reason it is not, and why its survivors are judged again.
class PointVerdict
  def initialize(point)
    @point = point
  end

  def safe? = @point.fits?(safe: true)

  def unsafe_reason = @point.reasons(Kimera::Reason.unsafety).first

  def revisit = @point.reasons(Kimera::Reason.revisiting).first
end
