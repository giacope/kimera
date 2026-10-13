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
    COMPARISONS = %i[> < >= <= == != !].freeze

    def call
      dir = sandbox.copy(fixture("silent"))
      report = run(dir)
      return { "pass" => false, "error" => report } if report.is_a?(String)
      measure(dir, report).then { |metrics| metrics.merge(verdicts) }.then { |metrics| finish(metrics) }
    end

    private

    def run(dir)
      path = File.join(dir, "tmp", "silent.json")
      result = checkout.kimera("run", "--report", path, "--no-progress", chdir: dir)
      return "no report (exit #{result.code}): #{result.output.lines.last(5).join}" unless File.exist?(path)
      @output = result.output
      JSON.parse(File.read(path, encoding: Encoding::UTF_8))
    end

    def measure(dir, report)
      files = Dir.glob("lib/**/*.rb", base: dir).sort
      silent = files.flat_map { |file| silent(dir, file, report) }
      { "candidate_lines" => @candidates, "silent_lines" => silent.size, "silent" => silent }
        .merge("unparseable_files" => @broken.size, "unreported_unparseable" => @broken.reject { |file| reported?(report, file) })
    end

    def silent(dir, file, report)
      @candidates ||= 0
      @broken ||= []
      parsed = Prism.parse_file(File.join(dir, file))
      return @broken << file && [] if parsed.failure?
      lines = candidates(parsed.value).uniq
      @candidates += lines.size
      lines.reject { |line| mutated?(report, file, line) || covered?(report, file, line) }.map { |line| "#{file}:#{line}" }
    end

    def candidates(node, inside = false, found = [])
      found << node.location.start_line if inside && candidate?(node)
      node.compact_child_nodes.each { |child| candidates(child, inside || body?(node, child), found) }
      found
    end

    def body?(node, child)
      case node
      when Prism::DefNode, Prism::BlockNode, Prism::LambdaNode then child.equal?(node.body)
      else false
      end
    end

    def candidate?(node)
      case node
      when Prism::CallNode then COMPARISONS.include?(node.name)
      when Prism::AndNode, Prism::OrNode, Prism::IfNode, Prism::UnlessNode, Prism::TrueNode, Prism::FalseNode then true
      else false
      end
    end

    def mutated?(report, file, line) = report.fetch("results").any? { |row| row["file"] == file && row["line"] == line }

    def regions(report) = Array(report["unmutated"])

    def covered?(report, file, line)
      regions(report).any? { |region| region["file"] == file && (region["start_line"]..region["end_line"]).cover?(line) }
    end

    def reported?(report, file) = regions(report).any? { |region| region["file"] == file }

    def verdicts
      run = differential(fixture("silent"), [%w[--jobs 1]]).values.first
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
  end
end
