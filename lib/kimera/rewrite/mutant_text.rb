# frozen_string_literal: true

require_relative "ast_walk"
require_relative "directive"
require_relative "numbered_params"
require_relative "../scribe"

class Kimera::Rewrite::MutantText
  def initialize(point, mutant, file:, root: ".")
    @point = point
    @mutant = mutant
    @file = file
    @root = root
  end

  def texts
    original = @point.to_h.fetch("original_source")
    [-> { directive.render(original) }, -> { placed { [] } }].lazy.flat_map(&:call).first(1)
  end

  private

  def directive = @mutant.rewrite(Kimera::Rewrite::Directive)

  def placed
    program = Kimera::Rewrite::NumberedParams.of(source).normalize
    found(program).map { |node| Kimera::Scribe.new(directive.apply(node)).at(program, node).source }
  rescue StandardError
    yield
  end

  def source = File.read(File.join(@root, @file), encoding: Encoding::UTF_8)

  def found(program)
    nodes = Kimera::Rewrite::AstWalk.new(program).to_enum(:visit)
    nodes.lazy.select { |node| @point.fits?(node: node) }.first(1)
  end
end
