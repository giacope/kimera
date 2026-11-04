# frozen_string_literal: true

require "json"
require "kimera/execution/child_process"
require "tmpdir"

RSpec.describe(Kimera::Execution::ChildProcess) do
  let(:reader) { Object.new.extend(described_class) }

  def parse(line, &) = reader.__send__(:parse, line, &)

  # A pipe read under a C locale tags the worker's UTF-8 bytes as US-ASCII.
  it "parses a worker's UTF-8 line whatever encoding the pipe tagged it with" do
    line = "{\"detail\":\"caf\xC3\xA9 \xE2\x80\xA6\"}\n".b.force_encoding(Encoding::US_ASCII)
    expect(parse(line)).to(eq("detail" => "café …"))
  end

  it "replaces bytes that aren't UTF-8 instead of failing the run" do
    line = "{\"detail\":\"\xFF\"}".b
    expect(parse(line)).to(eq("detail" => "�"))
  end

  it "leaves the line it was given untouched" do
    line = "{\"a\":1}".b
    parse(line)
    expect(line.encoding).to(eq(Encoding::BINARY))
  end

  # The descriptor itself moves, so code that writes to 1 or 2 without Ruby's
  # streams (a C extension, a subshell) writes to the null device too.
  # A file's descriptor, discarded: whether the stream answered is on it, where it then points, and what a
  # write to the stream took.
  def discarded
    Dir.mktmpdir do |dir|
      File.open(File.join(dir, "out.txt"), "w") do |file|
        stream = reader.__send__(:discard, file.fileno)
        [stream.fileno == file.fileno, File.readlink("/proc/self/fd/#{file.fileno}"), stream.write("x")]
      end
    end
  end

  it "points the descriptor itself at the null device, and answers a stream on it" do
    expect(discarded).to(eq([true, File::NULL, 1]))
  end

  it "hands a line that isn't JSON to its caller's block" do
    expect(parse("!!not json!!") { :unparsed }).to(eq(:unparsed))
  end

  describe "process groups" do
    def call(name, *) = reader.__send__(name, *)

    # A forked child that took the lead, and the process group it reports.
    def led
      group, report = IO.pipe
      pid =
        fork do
          call(:lead)
          report.puts(Process.getpgrp)
          exit!(0)
        end
      report.close
      [pid, Integer(group.gets)]
    ensure
      Process.wait(pid) if pid
    end

    it "makes a forked child lead a process group of its own" do
      pid, group = led
      expect(group).to(eq(pid))
    end

    # A session leader may not move to another group: what lead answers in a forked one, and its group.
    def unmoved
      said, told = IO.pipe
      pid =
        fork do
          Process.setsid
          told.puts(JSON.generate([call(:lead), Process.getpgrp]))
        ensure
          exit!(0)
        end
      told.close
      JSON.parse(said.read).tap { Process.wait(pid) }
    end

    it "leaves a child in the group it is in when it can't lead one of its own" do
      led, group = unmoved
      expect(led).to(eq(group))
    end

    it "kills a child and everything it started", :aggregate_failures do
      witness = self.witness
      pid = family(witness)
      call(:kill, pid)
      expect(Process.wait2(pid).last.termsig).to(eq(9))
      expect(witness.outlived?).to(be(false))
    end

    it "kills a child that never led a group of its own" do
      pid = fork { sleep(30) }
      call(:kill, pid)
      expect(Process.wait2(pid).last.termsig).to(eq(9))
    end

    it "reaps a child with the status it exited with, then kills what it left running", :aggregate_failures do
      witness = self.witness
      pid = family(witness) { exit!(3) }
      expect(call(:bury, pid).exitstatus).to(eq(3))
      expect(witness.outlived?).to(be(false))
    end

    it "shrugs off a process that is gone, answering why it could not signal it" do
      gone = fork { exit!(0) }.tap { |pid| Process.wait(pid) }
      expect(call(:signal, gone)).to(be_a(Errno::ESRCH))
    end

    # Processes as a user may not signal one they do not own.
    def foreign = Class.new { def kill(_signal, target) = raise(Errno::EPERM, target.to_s) }.new

    it "shrugs off a process out of reach, answering why it could not signal it" do
      expect(call(:signal, 12_345, foreign)).to(be_a(Errno::EPERM))
    end
  end
end
