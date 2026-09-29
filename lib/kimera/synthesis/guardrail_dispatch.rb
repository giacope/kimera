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

    def dispatch(rebuilt, bare, points)
      mutants = points.flat_map(&:mutants).reverse
      return parameter(rebuilt, mutants) if %i[optarg kwoptarg].include?(rebuilt.type)
      guarded = guard(mutants, rebuilt) { |mutant| variant(bare, mutant) }
      guarded.equal?(rebuilt) ? guarded : ast(:begin, guarded)
    end

    def branch(mutant, truthy, dispatch)
      id = mutant.id
      @applied << id
      conditional(active(id), truthy, dispatch)
    end

    def variant(bare, mutant)
      Kimera::Rewrite::Directive.apply(bare, mutant.directive)
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

    def active(id)
      ast(:send, ast(:const, ast(:cbase), :MutantRuntime), :active?, ast(:int, id))
    end

    def conditional(condition, truthy, fallback)
      ast(:if, condition, truthy, fallback)
    end
  end
end
