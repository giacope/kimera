# frozen_string_literal: true

require_relative "../origin"
require_relative "../redefinition"
require_relative "held"

class Kimera::Execution::BlockMethods; end

class Kimera::Execution::BlockMethods::Site
  def initialize(name, line, span, source)
    @name = name
    @line = line
    @span = span
    @source = source
  end

  def live?(locations) = locations.any? { |location| location.inside?(*@span) }

  def over(woven) = woven.placed(@line)

  def held(holder, path)
    redefinition = Kimera::Execution::Redefinition.new(holder, @name)
    redefinition.held(Kimera::Execution::BlockMethods::Held, self) { |definition| from?(definition, path) }
  end

  def compiled(path) = (@_compiled ||= {})[path] ||= @source.compiled(path, @line)

  protected

  def placed(line) = self.class.new(@name, line, @span, @source)

  private

  def from?(method, path)
    file, line = method.source_location
    line == @line && Kimera::Execution::Origin.new(file).canonical == path
  end
end
