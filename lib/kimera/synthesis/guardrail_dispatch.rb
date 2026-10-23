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
      return parameter(rebuilt, mutants) if PARAMETERS.key?(rebuilt.type)
      hidden, shown = mutants.partition { |mutant| mutant.directive[Kimera::Rewrite::TYPE] == PRIVATIZE }
      guard(shown, hidden.empty? ? rebuilt : privatized(rebuilt, hidden)) { |mutant| variant(bare, mutant) }
    end

    def privatized(rebuilt, hidden)
      defined = rebuilt.copy(body: statements([probe(hidden), *[rebuilt.body].compact]))
      statements([defined, *registrations(rebuilt.name, hidden)])
    end

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
      original.copy(value: guard(mutants, original.value) { snippet(failure) })
    end

    def guard(mutants, seed)
      mutants.reduce(seed) { |chain, mutant| branched(active(mutant.id), yield(mutant), chain) }
    end

    def active(id) = snippet("::Kimera::RUNTIME.active?(#{Integer(id)})")
  end
end
