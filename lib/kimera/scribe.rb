# frozen_string_literal: true

require_relative "parsing/syntax"
require_relative "parsing/unescaped"
require_relative "scribe/level"
require_relative "scribe/shape"
require_relative "scribe/binders"
require_relative "scribe/texts"
require_relative "scribe/place"
require_relative "scribe/pen"
require_relative "scribe/quote"
require_relative "scribe/number"
require_relative "scribe/name"
require_relative "scribe/lines"
require_relative "scribe/clauses"
require_relative "scribe/form"
require_relative "scribe/literals"
require_relative "scribe/strings"
require_relative "scribe/collections"
require_relative "scribe/assignments"
require_relative "scribe/calls"
require_relative "scribe/blocks"
require_relative "scribe/definitions"
require_relative "scribe/control"
require_relative "scribe/branches"
require_relative "scribe/rescues"
require_relative "scribe/patterns"

module Kimera
  class Scribe
    FORMS = [
      Keyword, Variable, Reference, Local, Numeral, Atom, Characters, Command, Path, Embedded,
      InterpolatedString, InterpolatedSymbol, InterpolatedCommand, Pattern, Sequence, Parentheses, Elements,
      Arguments, Pairs, Pair, Splat, Span, Assignment, Compound, Targets, Multiple, Attribute, Call, Invocation,
      Lambda, BlockParameters, Parameters, Parameter, Definition, Namespace, Condition, Unless, Selection,
      Arm, Loop, Iteration,
      Jump, Connective, Bracketed, Rescued, Exchange, Hook, Capture, Shareable, Matching, Alternatives,
      ArrayPattern, HashPattern, Pin
    ].flat_map { |form| form::TYPES.map { |type| [type, form] } }.to_h.freeze
    ROOTED = %i[class_node module_node singleton_class_node parentheses_node].freeze

    class Unbound < StandardError
    end

    class Unreadable < StandardError
    end

    def self.parse(source)
      result = Kimera::Syntax.parse(source)
      result.success? ? result.value : raise(Unreadable, result.errors.first.message)
    end

    def initialize(node, place = Place.top)
      @node = node
      @place = place
    end

    def source
      closed?(body) ? "#{text}\n" : text
    end

    def at(root, original) = Scribe.new(@node, Place.of(root, original))

    def over(root, original) = Scribe.new(@node, Place.of(root, original, original.location.end_line))

    def joined = Scribe.new(@node, @place.joined)

    def unbroken = Scribe.new(@node, @place.unbroken)

    def after(node) = Scribe.new(@node, @place.after(node))

    def text
      depth = @place.depth
      pen = Pen.new(binders, Pen::Margin.new(depth: depth, flat: @place.flat?), @place.locals)
      Lines.new(body, pen, @place.joint).text.delete_prefix("\n#{Pen::INDENT * depth}")
    end

    private

    def binders = Binders.new(Texts.new(@place.slices))

    def body = @node&.type == :program_node ? @node.statements : @node

    def closed?(statements)
      return false unless statements
      list = statements.type == :statements_node ? statements.body : [statements]
      list.size > 1 || (list.one? && ROOTED.include?(list.first.type))
    end
  end
end
