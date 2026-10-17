# frozen_string_literal: true

module Kimera
  module GuardrailDispatch
    DEFINITIONS = %i[def defs].freeze
    CLAUSED = %i[rescue ensure].freeze

    private

    def group(points)
      points.group_by do |point|
        location = point.location
        [location.start_offset, location.finish]
      end
    end

    def dispatch(rebuilt, bare, points)
      mutants = points.flat_map(&:mutants).reverse
      type = rebuilt.type
      return parameter(rebuilt, mutants) if %i[optarg kwoptarg].include?(type)
      return definition(rebuilt, bare, mutants) if mutants.any? && DEFINITIONS.include?(type)
      guarded = guard(mutants, rebuilt) { |mutant| variant(bare, mutant) }
      guarded.equal?(rebuilt) ? guarded : ast(:begin, guarded)
    end

    def definition(rebuilt, bare, mutants)
      children = rebuilt.children
      rebuilt.updated(nil, [*children[...-1], reshape(children.last, bare, mutants)])
    end

    def reshape(body, bare, mutants)
      guard(mutants, enclosed(body)) { |mutant| enclosed(variant(bare, mutant).children.last) }
    end

    def enclosed(body) = body && CLAUSED.include?(body.type) ? ast(:kwbegin, body) : body

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
      ast(:send, ast(:const, ast(:const, ast(:cbase), :Kimera), :RUNTIME), :active?, ast(:int, id))
    end

    def conditional(condition, truthy, fallback)
      ast(:if, condition, truthy, fallback)
    end
  end
end
