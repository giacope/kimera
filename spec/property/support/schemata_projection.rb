# frozen_string_literal: true

require "kimera/registry/builder"
require "kimera/synthesis/overlay"

module SchemataProjection
  CHAINS = %i[and_node or_node].freeze
  INTERPOLATED = %i[
    interpolated_string_node interpolated_symbol_node interpolated_x_string_node interpolated_regular_expression_node
  ].freeze
  NUMERIC = %i[integer_node float_node rational_node imaginary_node].freeze
  DEFAULTS = { optional_parameter_node: ["argument", "%s"], optional_keyword_parameter_node: ["keyword", "%s:"] }.freeze
  PARAMETERS = %i[requireds optionals rest posts keywords keyword_rest block].freeze
  FORMS = { statements_node: :sequence, string_node: :text, parameters_node: :parameters, begin_node: :clauses }
    .merge(CHAINS.to_h { |type| [type, :chain] }, INTERPOLATED.to_h { |type| [type, :interpolation] })
    .merge(DEFAULTS.keys.to_h { |type| [type, :required] }).freeze
  VOID = Object.new.freeze
  FLAG = /\A(?!forced_).*\?\z/

  module_function

  def check(source, operators: Kimera::Operators.build(keys: ["all"]))
    registry = Kimera::RegistryScan.new(operators: operators, shielded: false).source(source, file: "x.rb")
    overlay = Kimera::Overlay.new(registry)
    Case.new(source, registry, overlay, overlay.synthesize("x.rb", source))
  end

  Case =
    Struct.new(:source, :registry, :overlay, :result) do
      def schemata = @_schemata ||= SchemataProjection.read(result.source)

      def original
        map = Kimera::SourceMap.new(source)
        SchemataProjection.canon(Kimera::Scribe.new(Kimera::Guardrail.new(map, []).tree).source)
      end

      def baked(id) = SchemataProjection.canon(overlay.bake("x.rb", source, id))

      def projected(id) = SchemataProjection.normal(SchemataProjection.project(schemata, id))

      def mismatches
        result.mutant_ids.filter_map do |id|
          got = projected(id)
          want = baked(id)
          [id, got, want] unless got == want
        end
      end

      def guards = SchemataProjection.guards(schemata)
    end

  def canon(source) = normal(read(source))

  def read(source) = Kimera::Rewrite::NumberedParams.new(Kimera::Scribe.parse(source)).normalize

  def runtime?(node) = node&.type == :constant_path_node && node.name == :RUNTIME

  def called(node, name)
    return unless node.type == :call_node && node.name == name && runtime?(node.receiver)
    node.arguments.arguments.first.value
  end

  def guard(node) = (called(node.predicate, :active?) if node.type == :if_node)

  def taken(node, active)
    id = guard(node)
    return [id == active ? node.statements : node.subsequent&.statements] if id
    ids = spliced(node)
    [ids.include?(active) ? node.subsequent&.statements : node.statements] if ids
  end

  def spliced(node)
    test = node.predicate if node.type == :if_node
    return unless test&.type == :call_node && test.name == :! && test.receiver
    tested(lone(test.receiver))
  end

  def tested(node)
    return [*tested(node.left), *tested(node.right)] if node.type == :or_node
    id = called(node, :active?)
    id ? [id] : (raise ArgumentError, "not a guard: #{node.slice}")
  rescue ArgumentError
    nil
  end

  def project(node, active)
    return node unless node.is_a?(Prism::Node)
    branch = taken(node, active)
    return branch.first ? project(branch.first, active) : VOID if branch
    return statement("nil") if called(node, :active?)
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

  def revealed(node, active) = active ? statement("private(:#{node.arguments.arguments[2].unescaped})") : VOID

  def statement(source) = Kimera::Scribe.parse(source).statements.body.first

  def guards(node, found = [])
    return found unless node.is_a?(Prism::Node)
    found.concat([guard(node), *spliced(node)].compact)
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

  def lone(node)
    case node.type
    when :statements_node then (kept(node.body) in [only]) ? lone(only) : node
    when :parentheses_node then node.body ? lone(node.body) : node
    when :begin_node then clauses?(node) ? node : lone(node.statements)
    else node
    end
  end

  def clauses?(node) = !node.statements || [node.rescue_clause, node.ensure_clause, node.else_clause].any?

  def clauses(node)
    bare = settled(node)
    clauses?(bare) ? tree(bare) : normal(bare.statements)
  end

  def caught_clauses(node) = Kimera::Rescues.new(node.rescue_clause).to_a.filter_map { |clause| caught(clause) }

  def settled(node)
    linked = caught_clauses(node).reverse.reduce(nil) { |rest, clause| clause.copy(subsequent: rest) }
    ensured = node.ensure_clause if ran?(node.ensure_clause)
    return node.copy(rescue_clause: linked, ensure_clause: ensured) if linked || !node.else_clause
    folded(node.copy(ensure_clause: ensured))
  end

  def ran?(clause) = Array(clause&.statements&.body).any?

  def folded(node)
    rest = node.else_clause.statements
    body = node.statements ? node.statements.copy(body: [*node.statements.body, *rest&.body]) : rest
    node.copy(rescue_clause: nil, else_clause: nil, statements: body)
  end

  def caught(clause)
    splat = clause.exceptions.first if clause.exceptions.one?
    splat&.type == :splat_node ? listed(clause, lone(splat.expression)) : clause
  end

  def listed(clause, held)
    return clause.copy(exceptions: []) if held.type == :constant_path_node && held.slice.end_with?("::StandardError")
    return clause unless held.type == :array_node
    clause.copy(exceptions: held.elements) if held.elements.any?
  end

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
    fields =
      node.deconstruct_keys(nil).except(:node_id, :location, :locals).reject do |field, _|
        field.end_with?("_loc")
      end
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

  def worded(error)
    message = error.message
    return message unless error.instance_of?(ArgumentError)
    return "missing keyword: #{::Regexp.last_match(1)}" if message =~ /\Amissing keyword: :?(\w+)\z/
    return "arity" if message.match?(/\A(wrong number of arguments|missing argument: )/)
    message.match?(COMPARED) ? "comparison failed" : message
  end
end
