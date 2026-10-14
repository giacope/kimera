#!/usr/bin/env ruby
# frozen_string_literal: true

# Independent oracle for mutation-testing reports.
#
#   ruby oracle.rb PROJECT_DIR REPORT.json [--json OUT.json] [--jobs N] [--timeout SECS]
#
# For every mutant in the report it copies the project (lib/, spec/, .kimera.yml)
# into a fresh temp dir, applies the mutant by textual replacement of the
# reported source span (line/column .. end_line/end_column, which must contain
# exactly the report's "original" text), runs plain `rspec` in a brand-new
# process, and records killed (rspec non-zero / timeout) or survived (rspec 0).
#
# A mutant is "skipped" (not comparable) when it cannot be applied
# unambiguously: the span does not hold `original` and `original` does not
# occur exactly once on the reported lines, the mutated file is not valid Ruby,
# or a "(statement deleted)" mutant gives different verdicts depending on
# whether the statement is removed outright or replaced by `nil`.

require "json"
require "open3"
require "tmpdir"
require "fileutils"
require "timeout"

class Oracle
  DELETED = "(statement deleted)"

  def initialize(project, report_path, jobs: 4, timeout: 30)
    @project = File.expand_path(project)
    @report = JSON.parse(File.read(report_path))
    @jobs = jobs
    @timeout = timeout
  end

  def run
    base = rspec_in(copy_project) { |_dir| }
    abort "oracle: unmutated suite fails in #{@project}" unless base == :survived

    results = @report.fetch("results")
    queue = Queue.new
    results.each_with_index { |r, i| queue << [r, i] }
    out = Array.new(results.size)
    Array.new(@jobs) do
      Thread.new do
        loop do
          r, i = begin
            queue.pop(true)
          rescue ThreadError
            break
          end
          out[i] = judge(r)
        end
      end
    end.each(&:join)
    summarize(out)
  end

  private

  def file_of(r) = r["file"] || r["path"]
  def replacement_of(r) = r["mutated"] || r["replacement"]

  def judge(r)
    rec = {
      "id" => r["mutant_id"], "file" => file_of(r), "line" => r["line"],
      "tool" => r["status"], "original" => r["original"], "mutated" => replacement_of(r),
      "operator" => r["operator"], "label" => r["label"]
    }
    src_path = File.join(@project, file_of(r))
    source = File.read(src_path)
    repl = replacement_of(r)
    variants = repl == DELETED ? ["", "nil"] : [repl]
    verdicts = variants.map do |text|
      mutated = apply(source, r, text)
      next [:skip, "could not locate original text"] unless mutated
      next [:skip, "mutated source is not valid Ruby"] unless valid_ruby?(mutated)

      dir = copy_project
      [rspec_in(dir) { File.write(File.join(dir, file_of(r)), mutated) }, nil]
    end
    skip = verdicts.find { |v, _| v == :skip }
    if skip && verdicts.all? { |v, _| v == :skip }
      rec["oracle"] = "skipped"
      rec["reason"] = skip[1]
    elsif verdicts.map(&:first).reject { _1 == :skip }.uniq.size > 1
      rec["oracle"] = "skipped"
      rec["reason"] = "deletion verdict depends on delete-vs-nil"
    else
      rec["oracle"] = verdicts.map(&:first).find { _1 != :skip }.to_s
    end
    rec
  end

  # Replace the reported span; fall back to a unique occurrence on the lines.
  def apply(source, r, text)
    lines = source.lines
    l1, c1, l2, c2 = r.values_at("line", "column", "end_line", "end_column")
    orig = r["original"]
    return nil unless l1 && orig

    l2 ||= l1
    if c1 && c2 && l1 >= 1 && l2 <= lines.size
      start = lines[0...(l1 - 1)].sum(&:length) + (c1 - 1)
      stop = lines[0...(l2 - 1)].sum(&:length) + c2 # end_column is inclusive, 1-based
      if source[start...stop] == orig
        return source[0...start] + text + source[stop..]
      end
    end
    region = lines[(l1 - 1)..(l2 - 1)]&.join
    return nil unless region && region.scan(orig).size == 1

    pre = lines[0...(l1 - 1)].join
    post = lines[l2..]&.join.to_s
    pre + region.sub(orig) { text } + post
  end

  def valid_ruby?(code)
    _o, _e, st = Open3.capture3("ruby", "-c", stdin_data: code)
    st.success?
  end

  def copy_project
    dir = Dir.mktmpdir("oracle-")
    %w[lib spec .kimera.yml .rspec].each do |e|
      src = File.join(@project, e)
      FileUtils.cp_r(src, dir) if File.exist?(src)
    end
    dir
  end

  def rspec_in(dir)
    yield dir
    env = ENV.to_h.reject { |k, _| k.start_with?("BUNDLE", "RUBYOPT", "RUBYLIB", "GRADER") }
    pid = nil
    out_r, out_w = IO.pipe
    pid = Process.spawn(env, "rspec", chdir: dir, out: out_w, err: out_w, unsetenv_others: true, pgroup: true)
    out_w.close
    reader = Thread.new { out_r.read }
    status = nil
    begin
      Timeout.timeout(@timeout) { _, status = Process.wait2(pid) }
    rescue Timeout::Error
      Process.kill("KILL", -pid) rescue nil
      Process.wait(pid) rescue nil
      reader.join
      return :killed # timeout counts as detected
    end
    reader.join
    status.success? ? :survived : :killed
  ensure
    FileUtils.rm_rf(dir)
  end

  def summarize(recs)
    comparable = recs.select { |r| %w[killed survived].include?(r["tool"]) && r["oracle"] != "skipped" }
    other_status = recs.reject { |r| %w[killed survived].include?(r["tool"]) }
    skipped = recs.select { |r| %w[killed survived].include?(r["tool"]) && r["oracle"] == "skipped" }
    agree = comparable.count { |r| r["tool"] == r["oracle"] }
    false_surv = comparable.select { |r| r["tool"] == "survived" && r["oracle"] == "killed" }
    false_kill = comparable.select { |r| r["tool"] == "killed" && r["oracle"] == "survived" }
    {
      "project" => File.basename(@project),
      "total" => recs.size,
      "compared" => comparable.size,
      "agree" => agree,
      "agreement" => comparable.empty? ? nil : (100.0 * agree / comparable.size).round(1),
      "false_survivors" => false_surv,
      "false_kills" => false_kill,
      "skipped" => skipped,
      "other_status" => other_status.map { |r| r.slice("id", "tool", "file", "line") },
      "records" => recs
    }
  end
end

def fmt(r) = "##{r['id']} #{r['file']}:#{r['line']} [#{r['original'].to_s.lines.first&.strip} => #{r['mutated'].to_s.lines.first&.strip}]"

if $PROGRAM_NAME == __FILE__
  args = ARGV.dup
  json_out = (i = args.index("--json")) ? args.slice!(i, 2)[1] : nil
  jobs = (i = args.index("--jobs")) ? args.slice!(i, 2)[1].to_i : 4
  tmo = (i = args.index("--timeout")) ? args.slice!(i, 2)[1].to_i : 30
  project, report = args
  abort "usage: ruby oracle.rb PROJECT_DIR REPORT.json [--json OUT] [--jobs N] [--timeout S]" unless project && report

  s = Oracle.new(project, report, jobs: jobs, timeout: tmo).run
  puts "#{s['project']}: #{s['total']} mutants, compared #{s['compared']}, agree #{s['agree']} (#{s['agreement'] || 'n/a'}%), " \
       "skipped #{s['skipped'].size}, other statuses #{s['other_status'].size}"
  puts "  false survivors (tool survived, oracle killed): #{s['false_survivors'].size}"
  s["false_survivors"].each { |r| puts "    #{fmt(r)}" }
  puts "  false kills (tool killed, oracle survived): #{s['false_kills'].size}"
  s["false_kills"].each { |r| puts "    #{fmt(r)}" }
  s["skipped"].each { |r| puts "  skipped #{fmt(r)}: #{r['reason']}" }
  s["other_status"].each { |r| puts "  other status ##{r['id']} #{r['tool']} #{r['file']}:#{r['line']}" }
  File.write(json_out, JSON.pretty_generate(s)) if json_out
end
