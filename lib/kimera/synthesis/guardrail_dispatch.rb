# frozen_string_literal: true

module Kimera
  module GuardrailDispatch
    PRIVATIZE = "privatize"
    PARAMETERS = { optional_parameter_node: "argument", optional_keyword_parameter_node: "keyword" }.freeze

    private

    def group(points)
      points.group_by do |point|
        location = point.location
        [location.start_offset, location.finish, point.node_type]
      end
    end

    def dispatch(rebuilt, bare, points)
      mutants = points.flat_map(&:mutants).reverse
      type = rebuilt.type
      return rebuilt if mutants.empty?
      return parameter(rebuilt, mutants) if PARAMETERS.key?(type)
      return definition(rebuilt, bare, mutants) if type == :def_node
      guarded = guard(mutants, rebuilt) { |mutant| variant(bare, mutant) }
      clausal?(rebuilt) ? guarded : grouped([guarded])
    end

    def clausal?(node) = node.type == :begin_node && !node.begin_keyword_loc

    def definition(rebuilt, bare, mutants)
      hidden, reshaped = mutants.partition { |mutant| mutant.directive[Kimera::Rewrite::TYPE] == PRIVATIZE }
      defined = rebuilt.copy(body: probed(reshape(rebuilt.body, bare, reshaped), hidden))
      hidden.empty? ? defined : statements([defined, *registrations(rebuilt.name, hidden)])
    end

    def reshape(body, bare, mutants)
      return body if mutants.empty?
      guard(mutants, body) do |mutant|
        variant(bare, mutant).then do |mutated|
          mutated.body if mutated.type == :def_node
        end
      end
    end

    def probed(body, hidden) = hidden.empty? ? body : statements([probe(hidden), *[body].compact])

    def probe(mutants) = guard(mutants, snippet("nil")) { snippet("nil") }

    def registrations(name, mutants)
      mutants.map { |mutant| snippet("::Kimera::RUNTIME.privatize(#{Integer(mutant.id)}, self, :#{name})") }
    end

    def variant(bare, mutant)
      Kimera::Rewrite::Directive.new(mutant.directive).apply(bare)
    end

    def parameter(original, mutants)
      kind = PARAMETERS.fetch(original.type)
      failure = %(raise(ArgumentError, "missing #{kind}: #{original.name}"))
      original.copy(value: grouped([guard(mutants, original.value) { snippet(failure) }]))
    end

    def guard(mutants, seed)
      mutants.reduce(seed) { |chain, mutant| branched(active(mutant.id), yield(mutant), chain) }
    end

    def active(id) = snippet("::Kimera::RUNTIME.active?(#{Integer(id)})")
  end
end
