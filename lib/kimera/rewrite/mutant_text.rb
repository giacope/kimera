# frozen_string_literal: true

require_relative "ast_walk"
require_relative "directive"
require_relative "numbered_params"
require_relative "../scribe"

class Kimera::Rewrite::MutantText
  UNWRITTEN = "(kimera could not write this mutant's text; its label says what changed)"

  def initialize(point, mutant, root: ".")
    @point = point
    @mutant = mutant
    @root = root
  end

  def text = directive.render(@point.original_source) || placed

  private

  def directive = Kimera::Rewrite::Directive.new(@mutant.directive)

  def placed
    program = Kimera::Rewrite::NumberedParams.new(Kimera::Scribe.parse(source)).normalize
    found(program)&.then { |node| Kimera::Scribe.new(directive.apply(node)).at(program, node).source }
  rescue StandardError
    nil
  end

  def source = File.read(File.join(@root, @point.file), encoding: Encoding::UTF_8)

  def found(program)
    nodes = Kimera::Rewrite::AstWalk.new(program).to_enum(:visit)
    nodes.find { |node| node.location.start_offset == @point.location.start_offset && same?(node) }
  end

  def same?(node) = node.type.to_s == @point.node_type && node.slice == @point.original_source
end
