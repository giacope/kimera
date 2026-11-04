# frozen_string_literal: true

require_relative "ast_walk"
require_relative "directive"
require_relative "numbered_params"
require_relative "../scribe"

class Kimera::Rewrite::MutantText
  def initialize(point, mutant, root: ".")
    @point = point
    @mutant = mutant
    @root = root
  end

  def texts = [-> { directive.render(@point.original_source) }, -> { placed { [] } }].lazy.flat_map(&:call).first(1)

  private

  def directive = @mutant.rewrite(Kimera::Rewrite::Directive)

  def placed
    program = Kimera::Rewrite::NumberedParams.of(source).normalize
    found(program).map { |node| Kimera::Scribe.new(directive.apply(node)).at(program, node).source }
  rescue StandardError
    yield
  end

  def source = File.read(File.join(@root, @point.file), encoding: Encoding::UTF_8)

  def found(program)
    nodes = Kimera::Rewrite::AstWalk.new(program).to_enum(:visit)
    nodes.lazy.select { |node| @point.location.starts_at?(node.location.start_offset) && same?(node) }.first(1)
  end

  def same?(node) = node.type.to_s == @point.node_type && node.slice == @point.original_source
end
