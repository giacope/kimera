# frozen_string_literal: true

require "kimera/registry/builder"
require "kimera/synthesis/overlay"

# Symbolic evaluation of a mutant schemata. Fixing which mutant is active
# decides every `::MutantRuntime.active?(id)` guard, so the guarded program
# reduces to one plain program. That program must be the mutant's bake (the
# single mutation applied directly), and with nothing active, the original:
# then warm runs judge exactly the code the report shows, for every input.
#
# Both sides are compared as parser ASTs up to rewrites that never change
# behavior, applied to both alike:
# - a lone expression in parentheses is that expression;
# - adjacent string parts join and empty ones drop (unparser splits them);
# - && and || chains are associative (unparser regroups them);
# - minus on a numeric literal is the negative literal (`-(1)` is `-1`).
#
# One more rewrite is an assumption, not a behavior-preserving identity:
# `required` reads a default that raises the missing-argument ArgumentError
# as a required parameter, because a guard can't change a signature. That is
# what the equivalence contract below allows, and schemata_spec checks it by
# running calls that omit arguments, not by this reduction.
#
# Equivalence contract. With an applied mutant active, the schemata behaves
# like that mutant's bake on every call (same return value, or same
# exception class and message), except for:
# - reflection: a removed default is still optional to Method#arity and
#   Method#parameters;
# - where a missing argument is reported: inside the method once earlier
#   defaults have run, not by the arity check at the call site, so the
#   backtrace differs and so does the wording ("missing argument: b" vs
#   "wrong number of arguments"; "missing keyword: c" vs ":c");
# - comparison failures: "comparison of A with B failed" names and orders its
#   operands by whichever VM path ran (`[x, y].max` compiles one way for
#   literals, another for computed elements), and guards change the shape.
# A default removal the schemata can't represent is not applied at all. One
# whose bake doesn't parse (a middle optional, or one before a splat) is
# never emitted. One that rebinds positional arguments, sits in a block
# (omitted block arguments bind to nil), or follows a default that isn't
# inert is judged by reload instead (Kimera::DefaultRemoval).
module SchemataProjection
  CHAINS = %i[and or].freeze
  INTERPOLATED = %i[dstr dsym xstr regexp].freeze
  NUMERIC = %i[int float rational complex].freeze
  DEFAULTS = { optarg: [:arg, "argument"], kwoptarg: [:kwarg, "keyword"] }.freeze

  module_function

  def check(source, operators: Kimera::Operators.build(keys: ["all"]))
    registry = Kimera::RegistryScan.new(operators: operators, shielded: false).source(source, file: "x.rb")
    overlay = Kimera::Overlay.new(registry)
    Case.new(source, registry, overlay, overlay.synthesize("x.rb", source))
  end

  Case =
    Struct.new(:source, :registry, :overlay, :result) do
      def schemata = @_schemata ||= Kimera::Unparse.parse(result.source)

      def original
        map = Kimera::SourceMap.new(source)
        SchemataProjection.canon(Kimera::Unparse.unparse(Kimera::Guardrail.new(map, []).tree))
      end

      def baked(id) = SchemataProjection.canon(overlay.bake("x.rb", source, id))

      def projected(id) = SchemataProjection.normal(SchemataProjection.project(schemata, id))

      # [id, projected, baked] for every applied mutant that disagrees.
      def mismatches
        result.mutant_ids.filter_map do |id|
          got = projected(id)
          want = baked(id)
          [id, got, want] unless got == want
        end
      end

      def guards = SchemataProjection.guards(schemata)
    end

  def canon(source) = normal(Kimera::Unparse.parse(source))

  def guard(node)
    return unless node?(node, :if)
    condition = node.children[0]
    return unless node?(condition, :send) && condition.children[1] == :active?
    receiver = condition.children[0]
    condition.children[2].children[0] if node?(receiver, :const) && receiver.children[1] == :MutantRuntime
  end

  def project(node, active)
    return node unless node.is_a?(Parser::AST::Node)
    id = guard(node)
    return project(node.children[id == active ? 1 : 2], active) if id
    node.updated(nil, node.children.map { |child| project(child, active) })
  end

  def guards(node, found = [])
    return found unless node.is_a?(Parser::AST::Node)
    id = guard(node)
    found << id if id
    node.children.each { |child| guards(child, found) }
    found
  end

  def normal(node)
    return node unless node.is_a?(Parser::AST::Node)
    simplify(Parser::AST::Node.new(node.type, node.children.map { |child| normal(child) }))
  end

  def simplify(node)
    type = node.type
    return node.children[0] if type == :begin && node.children.one? && node?(node.children[0])
    return chain(node) if CHAINS.include?(type)
    return interpolation(node) if INTERPOLATED.include?(type)
    return required(node) if DEFAULTS.key?(type)
    negated(node)
  end

  def negated(node)
    literal, selector, *rest = node.children
    return node unless node.type == :send && selector == :-@ && rest.empty? && NUMERIC.include?(literal&.type)
    Parser::AST::Node.new(literal.type, [-literal.children[0]])
  end

  def chain(node)
    Parser::AST::Node.new(:"#{node.type}_chain", operands(node, node.type))
  end

  def operands(node, type)
    return [node] unless node?(node, type) || node?(node, :"#{type}_chain")
    node.children.flat_map { |child| operands(child, type) }
  end

  def interpolation(node)
    parts = joined(node.children.flat_map { |child| node?(child, :dstr) ? child.children : [child] })
    return text("") if node.type == :dstr && parts.empty?
    return parts[0] if node.type == :dstr && parts.one? && string?(parts[0])
    Parser::AST::Node.new(node.type, parts)
  end

  def joined(parts)
    parts.reject { |part| string?(part) && part.children[0].empty? }.each_with_object([]) do |part, out|
      next out << part unless string?(part) && string?(out.last)
      out[-1] = text(out.last.children[0] + part.children[0])
    end
  end

  def required(node)
    name, default = node.children
    type, kind = DEFAULTS.fetch(node.type)
    missing = Parser::AST::Node.new(:const, [nil, :ArgumentError])
    return node unless default == Parser::AST::Node.new(:send, [nil, :raise, missing, text("missing #{kind}: #{name}")])
    Parser::AST::Node.new(type, [name])
  end

  COMPARED = /\Acomparison of (.+) with (.+) failed\z/

  # An error message up to the details the equivalence contract excludes
  # (see the top of this file); any other wording must match exactly.
  def worded(error)
    message = error.message
    return message unless error.instance_of?(ArgumentError)
    return "missing keyword: #{::Regexp.last_match(1)}" if message =~ /\Amissing keyword: :?(\w+)\z/
    return "arity" if message.match?(/\A(wrong number of arguments|missing argument: )/)
    message.match?(COMPARED) ? "comparison failed" : message
  end

  def node?(node, type = nil) = node.is_a?(Parser::AST::Node) && (type.nil? || node.type == type)
  def string?(node) = node?(node, :str)
  def text(value) = Parser::AST::Node.new(:str, [value])
end
