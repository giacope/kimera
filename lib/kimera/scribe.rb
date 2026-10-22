# frozen_string_literal: true

require_relative "scribe/reading"
require_relative "scribe/level"
require_relative "scribe/shape"
require_relative "scribe/binders"
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
  # Writes a parser-gem tree back as Ruby source that reads as the same tree,
  # and reads source into such a tree.
  class Scribe
    CLOSED = %i[class sclass module begin].freeze
    FORMS = [
      Keyword, Variable, Local, Reference, Numeral, Atom, Characters, Const, Dstr, Dsym, Xstr, RegularExpression,
      Sequence, Parentheses, Elements, Pairs, Pair, Arguments, Splat, Span, Assignment, Compound, Multiple,
      Call, Index, Invocation, Block, Parameters, Parameter, Nesting, Destructuring, Definition, Namespace, Condition,
      Selection, Arm, Loop, Iteration, Jump, Connective, Bracketed, Rescued, Ensured, Exchange, Hook, Capture, Bare,
      Matching, Alternatives, ArrayPattern, HashPattern, ConstPattern, Rest, Pin
    ].flat_map { |form| form::TYPES.map { |type| [type, form] } }.to_h.freeze

    SHAPES = {
      casgn: Const, send: Attribute, csend: Attribute, mlhs: Group, splat: Spread, index: Index, indexasgn: Index,
      restarg: Parameter
    }.freeze

    class Unbound < StandardError
    end

    def self.parse(source) = Reading.new(source).tree

    def initialize(node)
      @node = node
    end

    def source
      return "" unless @node
      text = Lines.new(@node, Pen.new(Binders.new)).text.delete_prefix("\n")
      CLOSED.include?(@node.type) ? "#{text}\n" : text
    end
  end
end
