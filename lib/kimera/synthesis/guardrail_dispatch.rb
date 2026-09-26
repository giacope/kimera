# frozen_string_literal: true

module Kimera
  module GuardrailDispatch
    private

    def group(points)
      points.group_by do |point|
        location = point.location
        [location.start_offset, location.finish]
      end
    end

    def dispatch(original, points)
      mutants = points.flat_map(&:mutants).reverse
      return parameter(original, mutants) if %i[optarg kwoptarg].include?(original.type)
      guarded = guard(mutants, original) { |mutant| variant(original, mutant) }
      guarded.equal?(original) ? guarded : ast(:begin, guarded)
    end

    def branch(mutant, truthy, dispatch)
      id = mutant.id
      @applied << id
      conditional(active(id), truthy, dispatch)
    end

    def variant(original, mutant)
      Kimera::Rewrite::Directive.apply(original, mutant.directive, unguard: method(:unwrap))
    end

    def parameter(original, mutants)
      name, default = original.children
      original.updated(nil, [name, ast(:begin, guard(mutants, default) { missing(original, name) })])
    end

    def guard(mutants, seed) = mutants.reduce(seed) { |chain, mutant| branch(mutant, yield(mutant), chain) }

    def missing(param, name)
      ast(
        :send, nil, :raise, ast(:const, nil, :ArgumentError),
        ast(:str, "missing #{param.type == :kwoptarg ? "keyword" : "argument"}: #{name}")
      )
    end

    def unwrap(node)
      return node unless type?(node, :begin)
      inner, extra = node.children
      return node unless guarded?(inner, extra)
      unwrap(inner.children[2])
    end

    def guarded?(inner, extra)
      !extra && type?(inner, :if) && active?(inner.children[0])
    end

    def active?(node)
      type?(node, :send) && node.children[1] == :active?
    end

    def active(id)
      ast(:send, ast(:const, ast(:cbase), :MutantRuntime), :active?, ast(:int, id))
    end

    def conditional(condition, truthy, fallback)
      ast(:if, condition, truthy, fallback)
    end
  end
end
