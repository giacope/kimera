# frozen_string_literal: true

require_relative "../support/unparse"
require_relative "../registry/builder"
require_relative "../rewrite/directive"

class Kimera::Operators::Audit
  OK = :ok
  UNRENDERABLE = :unrenderable
  IDENTICAL = :identical

  Finding =
    Data.define(:operator, :original, :label, :rendered, :verdict) do
      def ok? = verdict == OK

      def to_s = "#{operator}: #{label}\n  #{original}\n  -> #{rendered.inspect} (#{verdict})"
    end

  Rendering =
    Data.define(:original, :rendered) do
      def verdict
        return UNRENDERABLE unless rendered
        rendered == reprinted ? IDENTICAL : OK
      end
      private
      def reprinted
        Kimera::Unparse.unparse(Kimera::Unparse.parse(original))
      rescue StandardError
        original
      end
    end

  class << self
    def audit(operators, source, file: "audit.rb")
      new(operators).audit(source, file: file)
    end

    def faults(operators, source, file: "audit.rb")
      audit(operators, source, file: file).reject(&:ok?)
    end
  end

  def initialize(operators)
    @operators = operators
  end

  def audit(source, file: "audit.rb")
    scan(source, file).points.flat_map { |point| findings(point) }
  end

  private

  def operators = Array(@operators)

  def scan(source, file)
    Kimera::RegistryScan.new(operators: operators).source(source, file: file)
  end

  def findings(point)
    key, original, mutants = point.project(:operator, :original_source, :mutants)
    mutants.map { |mutant| finding(key, original, mutant) }
  end

  def finding(key, original, mutant)
    rendered = Kimera::Rewrite::Directive.render(original, mutant.directive)
    Finding.new(
      operator: key, original: original, label: mutant.label,
      rendered: rendered, verdict: Rendering.new(original, rendered).verdict
    )
  end
end
