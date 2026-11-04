# frozen_string_literal: true

module Kimera
  module GuardrailDispatch
    PRIVATIZE = "privatize"
    PARAMETERS = { optional_parameter_node: "argument", optional_keyword_parameter_node: "keyword" }.freeze

    class Parameter
      def initialize(node)
        @node = node
      end

      def optional? = PARAMETERS.key?(@node.type)

      def missing = %(raise(ArgumentError, "missing #{PARAMETERS.fetch(@node.type)}: #{@node.name}"))
    end

    private

    def group(points)
      points.group_by { |point| point.location.anchor(point.node_type) }
    end

    def dispatch(rebuilt, bare, points)
      mutants = points.flat_map(&:mutants).reverse
      return parameter(rebuilt, mutants) if PARAMETERS.key?(rebuilt.type)
      hidden, shown = mutants.partition { |mutant| mutant.rewrite(Kimera::Rewrite::Directive).kind?(PRIVATIZE) }
      guard(shown, hidden.empty? ? rebuilt : privatized(rebuilt, hidden)) { |mutant| variant(bare, mutant) }
    end

    def privatized(rebuilt, hidden)
      defined = rebuilt.copy(body: statements([probe(hidden), *[rebuilt.body].compact]))
      statements([defined, *registrations(rebuilt.name, hidden)])
    end

    def probe(mutants) = guard(mutants, snippet("nil")) { snippet("nil") }

    def registrations(name, mutants)
      mutants.map { |mutant| snippet("::Kimera::RUNTIME.privatize(#{Integer(mutant)}, self, :#{name})") }
    end

    def variant(bare, mutant)
      mutant.rewrite(Kimera::Rewrite::Directive).apply(bare)
    end

    def parameter(original, mutants)
      kind = PARAMETERS.fetch(original.type)
      failure = %(raise(ArgumentError, "missing #{kind}: #{original.name}"))
      original.copy(value: guard(mutants, original.value) { snippet(failure) })
    end

    def guard(mutants, seed)
      mutants.reduce(seed) { |chain, mutant| branched(active(mutant.to_i), yield(mutant), chain) }
    end

    def active(id) = snippet("::Kimera::RUNTIME.active?(#{Integer(id)})")
  end
end
