# frozen_string_literal: true

require "fileutils"
require "kimera/execution/captured_methods"
require "tmpdir"

RSpec.describe(Kimera::Execution::CapturedMethods) do
  let(:dir) { Dir.mktmpdir }
  let(:file) { File.join(dir, "lib", "coerce.rb") }

  def inside
    FileUtils.mkdir_p(File.dirname(file))
    File.write(file, "")
    stub_const("CapturedCoerce", Module.new)
    yield
  ensure
    FileUtils.remove_entry(dir)
  end

  def load(code, path = file) = CapturedCoerce.module_eval(code, path, 1)

  def cause = described_class.new(dir).cause

  def taken(*names) = names.map { |name| CapturedCoerce.method(name) }

  def dropped = taken(:to_int).clear

  def unswept
    GC.disable
    100.times { dropped }
    load("\ndef self.to_int(v) = Integer(v) + 0\n")
    cause
  ensure
    GC.enable
  end

  it "says nothing of a Method object nothing holds any more" do
    inside do
      load("def self.to_int(v) = Integer(v)\n")
      expect(unswept).to(be_nil)
    end
  end

  def redefined
    load("def self.to_int(v) = Integer(v)\n")
    taken(:to_int).tap { load("\ndef self.to_int(v) = Integer(v) + 0\n") }
  end

  it "names a method taken at load that the same file redefined, and the file to leave out" do
    inside do
      held = redefined
      expect([cause, held.size]).to(
        eq(
          [
            "kimera redefined 1 method(s) the suite took as a Method object while it loaded " \
              "(CapturedCoerce.to_int at lib/coerce.rb:1): the one taken is no longer == the method and still " \
              "runs the code as loaded, where no mutant reaches; leave its file out of the run " \
              "(--exclude lib/coerce.rb)",
            1
          ]
        )
      )
    end
  end

  def after_ractor
    Warning[:experimental] = false
    child =
      fork do
        ractor = Ractor.new { 1 }
        ractor.respond_to?(:value) ? ractor.value : ractor.take
        exit!(yield ? 0 : 7)
      end
    Process.wait2(child).last.exitstatus
  end

  it "still names it in a process where a Ractor has run" do
    inside do
      held = redefined
      expect([after_ractor { cause }, held.size]).to(eq([0, 1]))
    end
  end

  def reaped
    Process.wait(-1, Process::WNOHANG)
  rescue Errno::ECHILD
    :none
  end

  def hooked(marker)
    armed = true
    at_exit { File.write(marker, "") if armed }
    [cause, reaped]
  ensure
    armed = false
  end

  it "scans in a child it reaps, which runs none of the suite's exit hooks", :aggregate_failures do
    inside do
      marker = File.join(dir, "hooked")
      expect(hooked(marker)).to(eq([nil, :none]))
      expect(File.exist?(marker)).to(be(false))
    end
  end

  def unbound(*names)
    load(names.map { |name| "def #{name} = 1\n" }.join)
    held = names.map { |name| CapturedCoerce.instance_method(name) }
    held.tap { load(names.map { |name| "def #{name} = 2\n" }.join) }
  end

  it "names an instance method taken unbound, three at most, and each file once", :aggregate_failures do
    inside do
      held = unbound(:a, :b, :c, :d)
      expect(cause).to(start_with("kimera redefined 4 method(s) the suite took as a Method object while it loaded"))
      expect([cause.scan(%r{CapturedCoerce#\w at lib/coerce\.rb:\d}).size, cause.scan("--exclude").size, held.size])
        .to(eq([3, 1, 4]))
    end
  end

  it "says nothing of a method still as it was taken, or redefined from another file", :aggregate_failures do
    inside do
      load("def self.kept = 1\ndef self.moved = 1\n")
      held = taken(:kept, :moved).tap { load("def self.moved = 2\n", File.join(dir, "lib", "other.rb")) }
      expect([cause, held.size]).to(eq([nil, 2]))
    end
  end

  def far = File.join(Dir.tmpdir, "captured_far.rb")

  it "says nothing of a file outside the project" do
    inside do
      load("def self.far = 1\n", far)
      held = taken(:far).tap { load("def self.far = 2\n", far) }
      expect([cause, held.size]).to(eq([nil, 1]))
    end
  end

  it "says nothing of a method its module dropped" do
    inside do
      load("def self.gone = 1\n")
      held = taken(:gone).tap { CapturedCoerce.singleton_class.remove_method(:gone) }
      expect([cause, held.size]).to(eq([nil, 1]))
    end
  end
end
