# frozen_string_literal: true

require "optparse"

module KimeraEval
  class Command
    FLAGS = [
      ["--kimera PATH", "kimera checkout to evaluate"],
      ["--only IDS", "comma-separated gap ids", ->(ids) { ids.split(",") }],
      ["--out FILE", "where to write the JSON scoreboard"],
      ["--quick", "skip the slow corpora and the deep checks"],
      ["--keep", "keep the sandbox for inspection"],
      ["--baseline FILE", "exit 1 on a failure FILE does not record"]
    ].freeze

    def initialize(out: $stdout, errors: $stderr)
      @out = out
      @errors = errors
    end

    def run(argv)
      given = parse(argv)
      checkout = Checkout.new(given.fetch(:kimera))
      checkout.prepare!
      board = evaluate(checkout, Selection.new(given[:only], given[:quick]), given[:keep])
      Record.new(given.fetch(:out), given[:baseline]).finished(board, @out, @errors)
    end

    private

    def parse(argv)
      given = { out: File.join(RESULTS, "latest.json") }
      parser.parse!(argv, into: given)
      given[:kimera] ? given : abort("eval/run: --kimera PATH is required")
    end

    def parser
      OptionParser.new("Usage: eval/run --kimera PATH [options]") do |parser|
        FLAGS.each { |flag, help, read = :itself.to_proc| parser.on(flag, help) { |value| read.call(value) } }
      end
    end

    def evaluate(checkout, selection, keep)
      sandbox = Sandbox.new
      context = Context.new(checkout, sandbox, selection)
      Scoreboard.new(checkout).tap { |board| selection.each { |kind| measure(board, kind, context) } }
    ensure
      keep ? @errors.puts("eval: sandbox kept at #{sandbox.root}") : sandbox.remove!
    end

    def measure(board, kind, context)
      @errors.puts("eval: #{kind::ID} #{kind::TITLE}")
      started = clock
      result = attempt(kind, context)
      board.record(kind, result, clock - started)
      @errors.puts("eval: #{kind::ID} #{result["pass"] ? "pass" : "FAIL"} #{result["summary"]}")
    end

    def clock(now = Process.clock_gettime(Process::CLOCK_MONOTONIC)) = now

    def attempt(kind, context)
      context.judged(kind)
    rescue StandardError => error
      { "pass" => false, "error" => "#{error.class}: #{error.message}\n#{error.backtrace.first(5).join("\n")}" }
    end
  end
end
