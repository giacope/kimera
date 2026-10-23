# frozen_string_literal: true

require "fileutils"
require "kimera/execution/captured_methods"
require "tmpdir"

# R4-KL9: a Method taken at load (`REGISTERED = method(:to_int)`) is no
# longer == the method once the overlay redefines it from the same file.
RSpec.describe(Kimera::Execution::CapturedMethods) do
  let(:dir) { Dir.mktmpdir }
  let(:file) { File.join(dir, "lib", "coerce.rb") }

  before do
    FileUtils.mkdir_p(File.dirname(file))
    File.write(file, "")
    stub_const("CapturedCoerce", Module.new)
  end

  after { FileUtils.remove_entry(dir) }

  def load(code, path = file) = CapturedCoerce.module_eval(code, path, 1)

  def cause = described_class.new(dir).cause

  def taken(*names) = names.map { |name| CapturedCoerce.method(name) }

  it "names a method taken at load that the same file redefined, and the file to leave out" do
    load("def self.to_int(v) = Integer(v)\n")
    held = taken(:to_int)
    load("\ndef self.to_int(v) = Integer(v) + 0\n")
    expect([cause, held.size]).to(
      eq(
        [
          "kimera redefined 1 method(s) the suite took as a Method object while it loaded " \
            "(CapturedCoerce.to_int at lib/coerce.rb:1): the one taken is no longer == the method and still " \
            "runs the code as loaded, where no mutant reaches; leave its file out of the run (--exclude lib/coerce.rb)",
          1
        ]
      )
    )
  end

  def unbound(*names)
    load(names.map { |name| "def #{name} = 1\n" }.join)
    held = names.map { |name| CapturedCoerce.instance_method(name) }
    held.tap { load(names.map { |name| "def #{name} = 2\n" }.join) }
  end

  it "names an instance method taken unbound, three at most, and each file once", :aggregate_failures do
    held = unbound(:a, :b, :c, :d)
    expect(cause).to(start_with("kimera redefined 4 method(s) the suite took as a Method object while it loaded"))
    expect(cause.scan(%r{CapturedCoerce#\w at lib/coerce\.rb:\d}).size).to(eq(3))
    expect([cause.scan("--exclude").size, held.size]).to(eq([1, 4]))
  end

  it "says nothing of a method still as it was taken, or redefined from another file", :aggregate_failures do
    load("def self.kept = 1\ndef self.moved = 1\n")
    held = taken(:kept, :moved)
    load("def self.moved = 2\n", File.join(dir, "lib", "other.rb"))
    expect([cause, held.size]).to(eq([nil, 2]))
  end

  it "says nothing of a file outside the project" do
    far = File.join(Dir.tmpdir, "captured_far.rb")
    load("def self.far = 1\n", far)
    held = taken(:far).tap { load("def self.far = 2\n", far) }
    expect([cause, held.size]).to(eq([nil, 1]))
  end

  it "says nothing of a method its module dropped" do
    load("def self.gone = 1\n")
    held = taken(:gone).tap { CapturedCoerce.singleton_class.remove_method(:gone) }
    expect([cause, held.size]).to(eq([nil, 1]))
  end
end
