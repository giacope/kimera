# frozen_string_literal: true

require "fileutils"
require "json"
require "open3"
require "tmpdir"

# The traces as a TLA+ module, so TLC needs no JSON module to read them:
# arrays become sequences, hashes records.
class TraceModule
  def initialize(traces)
    @traces = traces
  end

  def to_s = "---- MODULE TraceData ----\nEXTENDS Integers\nTraces == #{literal(@traces)}\n====\n"

  private

  def literal(value)
    case value
    when Array then "<<#{value.map { |item| literal(item) }.join(", ")}>>"
    when Hash then "[#{value.map { |key, item| "#{key} |-> #{literal(item)}" }.join(", ")}]"
    when String then value.dump
    when true, false then value.to_s.upcase
    else value.to_s
    end
  end
end

# Checks logged pool runs (support/pool_trace.rb) against the model with TLC
# and formal/WorkerPoolTrace.tla: one TLC run per pool size, since the slots
# are a constant of the model. A trace is accepted when TLC matched all its
# steps; the report names, for each other trace, the first step no model
# step could take.
class TraceCheck
  ROOT = File.expand_path("../../..", __dir__)
  JAR = File.join(ROOT, "tmp", "tla2tools.jar")
  SPEC = File.join(ROOT, "formal", "WorkerPoolTrace.tla")
  MATCHED = /<<"matched", (\d+), (\d+)>>/

  def self.available? = system("java", "-version", out: File::NULL, err: File::NULL)

  # runs: [jobs, trace] pairs.
  def initialize(runs)
    @runs = runs
  end

  # [every trace accepted?, report]
  def verdict
    system(File.join(ROOT, "bin", "model-check"), "--fetch", exception: true)
    reports = @runs.group_by(&:first).map { |jobs, group| replayed("jobs #{jobs}", group.map(&:last)) }
    [reports.all?(&:first), reports.map(&:last).join]
  end

  private

  def replayed(name, traces)
    Dir.mktmpdir("traces") do |dir|
      FileUtils.cp([SPEC, File.join(File.dirname(SPEC), "WorkerPool.tla")], dir)
      File.write(File.join(dir, "TraceData.tla"), TraceModule.new(traces).to_s)
      judged(name, traces, explore(dir, configured(dir, traces)))
    end
  end

  def configured(dir, traces)
    File.join(dir, "Trace.cfg").tap { |config| File.write(config, constants(traces)) }
  end

  def constants(traces)
    <<~CFG
      CONSTANTS
        Ids = {#{(1..traces.flat_map { |trace| trace[:queue] }.max).to_a.join(", ")}}
        Slots = {#{traces.first[:slots].join(", ")}}
        None = 0
        Blocking = FALSE
      INIT TraceInit
      NEXT TraceNext
      INVARIANT Matched
    CFG
  end

  def explore(dir, config)
    Open3.capture2e(
      "java", "-cp", JAR, "tlc2.TLC", "-workers", "1", "-deadlock", "-cleanup",
      "-metadir", File.join(dir, "states"), "-config", File.basename(config), File.basename(SPEC), chdir: dir
    ).first
  end

  def judged(name, traces, output)
    matched = progress(output)
    lines = traces.each_with_index.map { |trace, index| line(name, index + 1, trace[:steps], matched) }
    return [true, lines.join] if lines.none? { |text| text.include?("REJECTED") }
    [false, lines.join + output.gsub(/^<<"matched".*\n/, "")]
  end

  def progress(output)
    output.scan(MATCHED).each_with_object(Hash.new(0)) do |(trace, steps), best|
      best[Integer(trace)] = [best[Integer(trace)], Integer(steps)].max
    end
  end

  def line(name, number, steps, matched)
    done = matched[number]
    return "#{name} trace #{number}: accepted, #{steps.size} steps\n" if done == steps.size
    "#{name} trace #{number}: REJECTED at step #{done + 1} of #{steps.size}: #{JSON.generate(steps[done])}\n"
  end
end
