# frozen_string_literal: true

require "prism"

module KimeraEval
  # K2: code kimera scans but neither mutates nor reports. A candidate line
  # is one inside a method, block or lambda body holding a node the default
  # operators mutate (a comparison, &&, ||, !, a condition, a boolean). It
  # is silent when no mutant starts on it and no reported region covers it.
  # A scanned file that does not parse must be reported too. The verdicts on
  # the new mutants are checked against the oracle.
  class SilentCase < Case
    ID = "K2"
    TITLE = "No silently unmutated code (define_method, blocks, unparseable files)"

    def call
      dir = sandbox.copy(fixture("silent"))
      report = scan(dir)
      return { "pass" => false, "error" => report } if report.is_a?(String)
      finish(Coverage.new(dir, report).to_h.merge(verdicts))
    end

    private

    def scan(dir)
      path = File.join(dir, "tmp", "silent.json")
      result = checkout.cli("run", "--report", path, "--no-progress", chdir: dir)
      return "no report (exit #{result.code}): #{result.output.lines.last(5).join}" unless File.exist?(path)
      JSON.parse(File.read(path, encoding: Encoding::UTF_8))
    end

    def verdicts
      run = differential(target(fixture("silent")), [%w[--jobs 1]]).values.first
      { "differential" => run.except("disagreements"), "disagreements" => run["disagreements"] }
    end

    def finish(metrics)
      bad = metrics["silent_lines"] + metrics["unreported_unparseable"].size
      wrong = metrics["differential"].values_at("false_survived", "false_killed").compact.sum
      metrics.merge("pass" => (bad + wrong).zero?, "summary" => summary(metrics, wrong))
    end

    def summary(metrics, wrong)
      { "silent_lines" => "#{metrics["silent_lines"]}/#{metrics["candidate_lines"]}" }
        .merge("unreported_unparseable" => metrics["unreported_unparseable"].size, "false_verdicts" => wrong)
        .merge("mutants" => metrics["differential"]["mutants"])
    end

    # The candidate lines of each scanned file, against what the report says.
    class Coverage
      COMPARISONS = %i[> < >= <= == != !].freeze
      BODIES = [Prism::DefNode, Prism::BlockNode, Prism::LambdaNode].freeze
      MARKS = [Prism::AndNode, Prism::OrNode, Prism::IfNode, Prism::UnlessNode, Prism::TrueNode, Prism::FalseNode].freeze

      def initialize(dir, report)
        @dir = dir
        @report = report
      end

      def to_h
        files = Dir.glob("lib/**/*.rb", base: @dir)
        parsed = files.to_h { |file| [file, Prism.parse_file(File.join(@dir, file))] }
        broken, fine = parsed.partition { |_file, result| result.failure? }.map(&:to_h)
        unreported = broken.keys.reject { reported?(it) }
        lines(fine).merge("unparseable_files" => broken.size, "unreported_unparseable" => unreported)
      end

      private

      def lines(parsed)
        found = parsed.flat_map { |file, result| candidates(result.value).uniq.map { |line| [file, line] } }
        silent = found.reject { |file, line| mutated?(file, line) || covered?(file, line) }
        { "candidate_lines" => found.size, "silent_lines" => silent.size, "silent" => silent.map { it.join(":") } }
      end

      def candidates(node, inside: false)
        (inside && candidate?(node) ? [node.location.start_line] : []) +
          node.compact_child_nodes.flat_map { |child| candidates(child, inside: inside || body?(node, child)) }
      end

      def body?(node, child) = BODIES.any? { |kind| node.is_a?(kind) } && child.equal?(node.body)

      def candidate?(node)
        node.is_a?(Prism::CallNode) ? COMPARISONS.include?(node.name) : MARKS.any? { node.is_a?(it) }
      end

      def mutated?(file, line) = @report.fetch("results").any? { |row| row["file"] == file && row["line"] == line }

      def regions = Array(@report["unmutated"])

      def covered?(file, line) = regions.any? { |region| region["file"] == file && span(region).cover?(line) }

      def span(region) = region["start_line"]..region["end_line"]

      def reported?(file) = regions.any? { |region| region["file"] == file }
    end
  end
end
