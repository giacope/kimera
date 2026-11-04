# frozen_string_literal: true

require_relative "../scribe"
require_relative "../registry/builder"
require_relative "../rewrite/directive"

class Kimera::Operators::Audit
  OK = :ok
  UNRENDERABLE = :unrenderable
  IDENTICAL = :identical

  class Finding
    def initialize(operator, original, label, rendered)
      @operator = operator
      @original = original
      @label = label
      @rendered = rendered
    end

    def ok? = verdict == OK

    def to_s = "#{@operator}: #{@label}\n  #{@original}\n  -> #{@rendered.inspect} (#{verdict})"

    private

    def verdict = @_verdict ||= Kimera::Operators::Audit::Rendering.new(@original, @rendered).verdict
  end

  class Rendering
    def initialize(original, rendered)
      @original = original
      @rendered = rendered
    end

    def verdict
      return UNRENDERABLE unless @rendered
      [@original, reprinted].include?(@rendered) ? IDENTICAL : OK
    end

    private

    def reprinted
      parsed = Kimera::Scribe.parse(@original)
      Kimera::Scribe.new(parsed).source
    rescue StandardError
      @original
    end
  end

  def initialize(operators)
    @operators = operators
  end

  def audit(source, file: "audit.rb")
    scan(source, file).points.flat_map { |point| findings(point) }
  end

  def faults(source) = audit(source).reject(&:ok?)

  private

  def operators = Array(@operators)

  def scan(source, file)
    Kimera::RegistryScan.new(operators: operators).source(source, file: file)
  end

  def findings(point)
    key, original, mutants = point.project(:operator, :original_source, :mutants)
    mutants.map do |mutant|
      Finding.new(key, original, mutant.label, Kimera::Rewrite::Directive.new(mutant.directive).render(original).first)
    end
  end
end
