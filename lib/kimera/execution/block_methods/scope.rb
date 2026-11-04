# frozen_string_literal: true

class Kimera::Execution::BlockMethods; end

class Kimera::Execution::BlockMethods::Scope
  def initialize(opening, usings)
    @opening = opening
    @usings = usings
  end

  def to_s = "#{@opening}#{@usings.join}"

  def refined(using) = self.class.new(@opening, [*@usings, using])
end
