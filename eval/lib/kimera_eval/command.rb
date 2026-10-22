# frozen_string_literal: true

require "optparse"

module KimeraEval
  Settings = Struct.new(:kimera, :out, :only, :quick, :keep, :baseline, keyword_init: true)

  # eval/run --kimera PATH [--only K1,K4] [--out FILE] [--quick] [--keep]
  #   [--baseline FILE]
  # With --baseline, exits 1 if a case fails that FILE does not record as
  # failing: a regression from the recorded scoreboard, or a new case that
  # does not pass. FILE is read before --out is written, so both can name
  # the same file.
  class Command
    FLAGS = [
      ["--kimera PATH", "kimera checkout to evaluate", ->(settings, path) { settings.kimera = path }],
      ["--only IDS", "comma-separated gap ids", ->(settings, ids) { settings.only = ids.split(",") }],
      ["--out FILE", "where to write the JSON scoreboard", ->(settings, file) { settings.out = file }],
      ["--quick", "skip the slow corpora and the deep checks", ->(settings, on) { settings.quick = on }],
      ["--keep", "keep the sandbox for inspection", ->(settings, on) { settings.keep = on }],
      ["--baseline FILE", "exit 1 on a failure FILE does not record", ->(settings, file) { settings.baseline = file }]
    ].freeze

    def initialize(out: $stdout, errors: $stderr)
      @out = out
      @errors = errors
    end

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
      settings.keep ? @errors.puts("eval: sandbox kept at #{sandbox.root}") : sandbox.remove!
    end

    def selected(settings)
      only = settings.only
      only ? CASES.select { |kind| only.include?(kind::ID) } : CASES
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
      kind.new(context).call
    rescue StandardError => error
      { "pass" => false, "error" => "#{error.class}: #{error.message}\n#{error.backtrace.first(5).join("\n")}" }
    end

    def finish(board, settings)
      baseline = settings.baseline
      worse = baseline ? board.failing - recorded(board, baseline) : []
      board.write(settings.out)
      @out.puts(board.markdown)
      verdict(worse, baseline)
    end

    def recorded(board, path) = board.failing(JSON.parse(File.read(path, encoding: Encoding::UTF_8)).fetch("cases"))

    def verdict(worse, baseline)
      return 0 if worse.empty?
      @errors.puts("eval: worse than #{baseline}: #{worse.join(" ")}")
      1
    end
  end
end
