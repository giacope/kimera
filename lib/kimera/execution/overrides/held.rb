# frozen_string_literal: true

require_relative "../origin"
require_relative "../redefinition"

class Kimera::Execution::Overrides; end

class Kimera::Execution::Overrides::Held
  WRAPPED =
    "another file redefined its method around the one it replaced (a memoizer that holds that method), and the " \
      "warm overlay keeps that definition, which never calls the mutated one; so a mutant no test reached warm is " \
      "judged again in a fresh mirror against the tests near its file"

  def initialize(redefinition, definition, visibility, span)
    @redefinition = redefinition
    @definition = definition
    @visibility = visibility
    @span = span
  end

  def restored(file)
    @redefinition.found.select { |fresh| here?(fresh, file) }.map do |fresh|
      @redefinition.redefine(@definition, @visibility)
      self.class.new(@redefinition, fresh, @visibility, @span)
    end
  end

  def reached?(aliases) = aliases.reaches?(@definition)

  def replacing(target, ancestors)
    named = ancestors.any? { |holder| Kimera::Execution::Redefinition.new(holder, target) == @redefinition }
    named ? [@definition] : []
  end

  def revisit!(points)
    lines = @span.start_line..@span.end_line
    covered = points.select { |point| point.fits?(safe: true, opening: lines) }
    covered.each { |point| point.mark!(Kimera::Reason.revisit(WRAPPED)) }
  end

  private

  def here?(method, file) = Kimera::Execution::Origin.new(method.source_location&.first).canonical == file
end
