# frozen_string_literal: true

require "kimera/registry/builder"
require "kimera/synthesis/overlay"

# Symbolic evaluation of a mutant schemata. Fixing which mutant is active
# decides every `::Kimera::RUNTIME.active?(id)` guard, so the guarded program
# reduces to one plain program. That program must be the mutant's bake (the
# single mutation applied directly), and with nothing active, the original:
# then warm runs judge exactly the code the report shows, for every input.
#
# Both sides are compared as Prism trees up to rewrites that never change
# behavior, applied to both alike:
# - a lone expression in parentheses is that expression;
# - adjacent string parts join and empty ones drop (writing may split them),
#   and an interpolated string literal is its string;
# - && and || chains are associative (writing may regroup them);
# - minus on a numeric literal is the negative literal (`-(1)` is `-1`);
# - a `nil` statement that is not a sequence's last is no statement (a
#   visibility mutant's coverage probe reduces to one);
# - a method's parameters are one list, whatever kind each is;
# - `begin ... end` is its body, and holding a rescue or ensure clause it is
#   the method body that holds that clause (a guarded method body needs the
#   begin; Ruby reads both alike).
#
# A visibility mutant is not a guard: `::Kimera::RUNTIME.privatize(k, self,
# :m)` registers a flip the runtime makes when k turns active, so it reduces
# to `private(:m)` with k active and to nothing otherwise.
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
  CHAINS = %i[and_node or_node].freeze
  INTERPOLATED = %i[
    interpolated_string_node interpolated_symbol_node interpolated_x_string_node interpolated_regular_expression_node
  ].freeze
  NUMERIC = %i[integer_node float_node rational_node imaginary_node].freeze
  DEFAULTS = { optional_parameter_node: ["argument", "%s"], optional_keyword_parameter_node: ["keyword", "%s:"] }.freeze
  PARAMETERS = %i[requireds optionals rest posts keywords keyword_rest block].freeze
  KEYWORDS = %i[begin_keyword_loc end_keyword_loc].freeze
  FORMS = { statements_node: :sequence, string_node: :text, parameters_node: :parameters }
    .merge(CHAINS.to_h { |type| [type, :chain] }, INTERPOLATED.to_h { |type| [type, :interpolation] })
    .merge(DEFAULTS.keys.to_h { |type| [type, :required] }).freeze
  VOID = Object.new.freeze
  # A predicate on a node, but not how a literal's encoding was spelled.
  FLAG = /\A(?!forced_).*\?\z/

  module_function

  def check(source, operators: Kimera::Operators.build(keys: ["all"]))
    registry = Kimera::RegistryScan.new(operators: operators, shielded: false).source(source, file: "x.rb")
    overlay = Kimera::Overlay.new(registry)
    Case.new(source, registry, overlay, overlay.synthesize("x.rb", source))
  end

  Case =
    Struct.new(:source, :registry, :overlay, :result) do
      def schemata = @_schemata ||= Kimera::Scribe.parse(result.source)

      def original
        map = Kimera::SourceMap.new(source)
        SchemataProjection.canon(Kimera::Scribe.new(Kimera::Guardrail.new(map, []).tree).source)
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

  def canon(source) = normal(Kimera::Scribe.parse(source))

  def runtime?(node) = node&.type == :constant_path_node && node.name == :RUNTIME

  def called(node, name)
    return unless node.type == :call_node && node.name == name && runtime?(node.receiver)
    node.arguments.arguments.first.value
  end

  def guard(node) = (called(node.predicate, :active?) if node.type == :if_node)

  def project(node, active)
    return node unless node.is_a?(Prism::Node)
    id = guard(node)
    return project(id == active ? node.statements : node.subsequent&.statements, active) if id
    hidden = called(node, :privatize)
    return revealed(node, hidden == active) if hidden
    rebuilt(node) { |child| project(child, active) }
  end

  def rebuilt(node, &)
    changes = node.deconstruct_keys(nil).filter_map { |field, value| [field, renewed(value, &)] if renewable?(value) }
    node.copy(**changes.to_h)
  end

  def renewable?(value) = value.is_a?(Prism::Node) || value.is_a?(Array)

  def renewed(value)
    return yield(value) if value.is_a?(Prism::Node)
    value.map { |item| item.is_a?(Prism::Node) ? yield(item) : item }.reject { |item| item.equal?(VOID) }
  end

  # A privatize guard is `private :name` while its mutant is active, and nothing otherwise.
  def revealed(node, active) = active ? statement("private(:#{node.arguments.arguments[2].unescaped})") : VOID

  def statement(source) = Kimera::Scribe.parse(source).statements.body.first

  def guards(node, found = [])
    return found unless node.is_a?(Prism::Node)
    id = guard(node)
    found << id if id
    node.compact_child_nodes.each { |child| guards(child, found) }
    found
  end

  def normal(node)
    return node unless node.is_a?(Prism::Node)
    inner = lone(node)
    return normal(inner) unless inner.equal?(node)
    simplify(node)
  end

  def simplify(node)
    form = FORMS[node.type]
    form ? public_send(form, node) : number(node) || tree(node)
  end

  def sequence(node) = [:statements, *kept(node.body).map { |statement| normal(statement) }]

  def text(node) = [:string, node.unescaped]

  def parameters(node)
    [:parameters, *PARAMETERS.flat_map { |field| Array(node.public_send(field)) }.map { |parameter| normal(parameter) }]
  end

  def chain(node) = [:"#{node.type}_chain", *operands(node, node.type).map { |operand| normal(operand) }]

  # A lone expression in parentheses, a sequence of one, or a bare begin.
  def lone(node)
    case node.type
    when :statements_node then (kept(node.body) in [only]) ? lone(only) : node
    when :parentheses_node then node.body ? lone(node.body) : node
    when :begin_node then clauses?(node) ? node : lone(node.statements)
    else node
    end
  end

  def clauses?(node) = !node.statements || [node.rescue_clause, node.ensure_clause, node.else_clause].any?

  def kept(body) = [*body[...-1].reject { |statement| lone(statement).type == :nil_node }, *body.last(1)]

  def operands(node, type)
    inner = lone(node)
    inner.type == type ? [*operands(inner.left, type), *operands(inner.right, type)] : [inner]
  end

  def number(node)
    return [node.type, node.value] if NUMERIC.include?(node.type)
    literal = normal(node.receiver) if negated?(node)
    [literal[0], -literal[1]] if literal && NUMERIC.include?(literal[0])
  end

  def negated?(node) = node.type == :call_node && node.name == :-@ && node.receiver && !(node.arguments || node.block)

  def tree(node)
    flags = node.class.instance_methods(false).grep(FLAG).sort.map { |flag| [flag, node.public_send(flag)] }
    fields = node.deconstruct_keys(nil).except(:node_id, :location, :locals, *(KEYWORDS if node.type == :begin_node))
    [node.type, *flags, *fields.map { |field, value| [field, part(value)] }]
  end

  def part(value)
    case value
    when Prism::Node then normal(value)
    when Prism::Location then true
    when Array then value.map { |item| part(item) }
    else value
    end
  end

  def interpolation(node)
    parts = joined(node.parts.flat_map { |part| pieces(part) })
    written = plain(parts) if node.type == :interpolated_string_node
    written || [node.type, *tree(node.copy(parts: []))[1..], parts]
  end

  # A string literal of no parts is "", and of one string part that string.
  def plain(parts)
    return [:string, ""] if parts.empty?
    parts.first if parts.one? && parts.first[0] == :string
  end

  def pieces(part)
    return part.parts.flat_map { |inner| pieces(inner) } if part.type == :interpolated_string_node
    written = normal(part.type == :embedded_statements_node && part.statements ? part.statements : part)
    [written]
  end

  def joined(parts)
    parts.reject { |part| part == [:string, ""] }.each_with_object([]) do |part, out|
      next out << part unless part[0] == :string && out.last&.first == :string
      out[-1] = [:string, out.last[1] + part[1]]
    end
  end

  def required(node)
    kind, spelling = DEFAULTS.fetch(node.type)
    missing = statement(%(raise(ArgumentError, "missing #{kind}: #{node.name}")))
    return tree(node) unless normal(node.value) == normal(missing)
    normal(statement("def kimera(#{format(spelling, node.name)}) = nil").parameters).last
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
end
