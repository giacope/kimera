# frozen_string_literal: true

require_relative "../rewrite/ast_walk"
require_relative "guardrail_factories"
require_relative "line_pad"

class Kimera::SpliceReopening
  include Kimera::GuardrailFactories

  class Target
    def initialize(node, lexical)
      @node = node
      @lexical = lexical
    end

    def to_s = path? ? @node.target.slice : @node.name_loc.slice

    def existing = "#{owner}.const_defined?(:#{name}, false) ? #{owner}.const_get(:#{name})"

    private

    def path? = @node.type == :constant_path_write_node

    def name = path? ? @node.target.name : @node.name

    def owner
      return @lexical unless path?
      @node.target.parent&.slice || "::Object"
    end
  end

  class Assignment
    def initialize(node, lexical, target = Target.new(node, lexical))
      @node = node
      @target = target
    end

    def edit = [@node.location.start_offset, opening, header]

    private

    def header = "#{@target} = (#{"\n" * lost}#{@target.existing} : #{factory}); #{@target}.class_eval "

    def opening = @node.value.block.location.start_offset

    def lost = Kimera::LinePad.new(@node.slice.byteslice(0, opening - @node.location.start_offset)).short(factory)

    def factory
      location = @node.value.location
      location.slice.byteslice(0, opening - location.start_offset).rstrip
    end
  end

  def initialize(map)
    @map = map
  end

  def edits = constants.map(&:edit)

  private

  def constants
    found = []
    Kimera::Rewrite::AstWalk.new(@map.ast).visit { |node| found << assignment(node) if reopenable?(node) }
    found
  end

  def assignment(node) = Assignment.new(node, LEXICAL)
end
