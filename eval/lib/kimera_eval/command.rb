# frozen_string_literal: true

require "optparse"

module KimeraEval
  Settings = Struct.new(:kimera, :out, :only, :quick, :keep, keyword_init: true)

  # eval/run --kimera PATH [--only K1,K4] [--out FILE] [--quick] [--keep]
  class Command
    FLAGS = [
      ["--kimera PATH", "kimera checkout to evaluate", ->(settings, path) { settings.kimera = path }],
      ["--only IDS", "comma-separated gap ids", ->(settings, ids) { settings.only = ids.split(",") }],
      ["--out FILE", "where to write the JSON scoreboard", ->(settings, file) { settings.out = file }],
      ["--quick", "skip the slow corpora and the deep checks", ->(settings, on) { settings.quick = on }],
      ["--keep", "keep the sandbox for inspection", ->(settings, on) { settings.keep = on }]
    ].freeze

    def run(argv)
      settings = parse(argv)
      checkout = Checkout.new(settings.kimera)
      checkout.prepare!
      finish(evaluate(checkout, settings), settings)
    end

    private

    def parse(argv)
      settings = Settings.new(out: File.join(RESULTS, "latest.json"))
      parser(settings).parse!(argv)
      settings.kimera ? settings : abort("eval/run: --kimera PATH is required")
    end

    def parser(settings)
      OptionParser.new("Usage: eval/run --kimera PATH [options]") do |parser|
        FLAGS.each { |flag, help, set| parser.on(flag, help) { |value| set.call(settings, value) } }
      end
    end

    def evaluate(checkout, settings)
      sandbox = Sandbox.new
      context = Context.new(checkout, sandbox, settings)
      Scoreboard.new(checkout).tap { |board| selected(settings).each { |kind| measure(board, kind, context) } }
    ensure
      settings.keep ? warn("eval: sandbox kept at #{sandbox.root}") : sandbox.remove!
    end

    def selected(settings)
      only = settings.only
      only ? CASES.select { |kind| only.include?(kind::ID) } : CASES
    end

    def measure(board, kind, context)
      warn("eval: #{kind::ID} #{kind::TITLE}")
      started = clock
      result = attempt(kind, context)
      board.record(kind, result, clock - started)
      warn("eval: #{kind::ID} #{result["pass"] ? "pass" : "FAIL"} #{result["summary"]}")
    end

    def clock(now = Process.clock_gettime(Process::CLOCK_MONOTONIC)) = now

    def attempt(kind, context)
      kind.new(context).call
    rescue StandardError => error
      { "pass" => false, "error" => "#{error.class}: #{error.message}\n#{error.backtrace.first(5).join("\n")}" }
    end

    def finish(board, settings)
      board.write(settings.out)
      puts(board.markdown)
      0
    end
  end
end
