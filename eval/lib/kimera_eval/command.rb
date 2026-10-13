# frozen_string_literal: true

require "optparse"

module KimeraEval
  # eval/run --kimera PATH [--only K1,K4] [--out FILE] [--quick] [--keep]
  class Command
    def run(argv)
      options = parse(argv)
      checkout = Checkout.new(options.fetch(:kimera))
      checkout.prepare!
      board = evaluate(checkout, options)
      finish(board, options)
    end

    private

    def parse(argv)
      options = { out: File.join(RESULTS, "latest.json"), only: nil, quick: false, keep: false }
      OptionParser.new do |parser|
        parser.banner = "Usage: eval/run --kimera PATH [options]"
        parser.on("--kimera PATH", "kimera checkout to evaluate") { |path| options[:kimera] = path }
        parser.on("--only IDS", "comma-separated gap ids") { |ids| options[:only] = ids.split(",") }
        parser.on("--out FILE", "where to write the JSON scoreboard") { |file| options[:out] = file }
        parser.on("--quick", "skip the slow corpora (dry-inflector, self-host)") { options[:quick] = true }
        parser.on("--keep", "keep the sandbox for inspection") { options[:keep] = true }
      end.parse!(argv)
      options.fetch(:kimera) { abort("eval/run: --kimera PATH is required") }
      options
    end

    def evaluate(checkout, options)
      sandbox = Sandbox.new
      context = Context.new(checkout, sandbox, options)
      Scoreboard.new(checkout).tap { |board| selected(options).each { |kind| measure(board, kind, context) } }
    ensure
      options[:keep] ? warn("eval: sandbox kept at #{sandbox.root}") : sandbox&.remove!
    end

    def selected(options)
      only = options[:only]
      only ? CASES.select { |kind| only.include?(kind::ID) } : CASES
    end

    def measure(board, kind, context)
      warn("eval: #{kind::ID} #{kind::TITLE}")
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      result = attempt(kind, context)
      board.record(kind, result, Process.clock_gettime(Process::CLOCK_MONOTONIC) - started)
      warn("eval: #{kind::ID} #{result["pass"] ? "pass" : "FAIL"} #{result["summary"]}")
    end

    def attempt(kind, context)
      kind.new(context).call
    rescue StandardError => e
      { "pass" => false, "error" => "#{e.class}: #{e.message}\n#{e.backtrace.first(5).join("\n")}" }
    end

    def finish(board, options)
      board.write(options.fetch(:out))
      puts(board.markdown)
      0
    end
  end
end
