# frozen_string_literal: true

class PointVerdict
  def initialize(point)
    @point = point
  end

  def safe? = @point.fits?(safe: true)

  def unsafe_reason = @point.reasons(Kimera::Reason.unsafety).first

  def revisit = @point.reasons(Kimera::Reason.revisiting).first
end
