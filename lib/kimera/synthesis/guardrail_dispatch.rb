# frozen_string_literal: true

module Kimera
  module GuardrailDispatch
    PRIVATIZE = "privatize"
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
      hidden, reshaped = mutants.partition { |mutant| mutant.directive[Kimera::Rewrite::TYPE] == PRIVATIZE }
      children = rebuilt.children
      defined = rebuilt.updated(nil, [*children[...-1], probed(reshape(children.last, bare, reshaped), hidden)])
      hidden.empty? ? defined : ast(:begin, defined, *registrations(children[-3], hidden))
    end

    def reshape(body, bare, mutants)
      guard(mutants, enclosed(body)) { |mutant| enclosed(variant(bare, mutant).children.last) }
    end

    def probed(body, hidden) = hidden.empty? ? body : ast(:begin, probe(hidden), *[body].compact)

    def enclosed(body) = body && CLAUSED.include?(body.type) ? ast(:kwbegin, body) : body

    def probe(mutants) = guard(mutants, ast(:nil)) { ast(:nil) }

    def registrations(name, mutants)
      mutants.map { |mutant| ast(:send, runtime, :privatize, ast(:int, mutant.id), ast(:self), ast(:sym, name)) }
    end

    def branch(mutant, truthy, dispatch)
      conditional(active(mutant.id), truthy, dispatch)
    end

    def variant(bare, mutant)
      Kimera::Rewrite::Directive.new(mutant.directive).apply(bare)
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
      ast(:send, runtime, :active?, ast(:int, id))
    end

    def runtime = ast(:const, ast(:const, ast(:cbase), :Kimera), :RUNTIME)

    def conditional(condition, truthy, fallback)
      ast(:if, condition, truthy, fallback)
    end
  end
end
