# frozen_string_literal: true

require "fileutils"
require "kimera/frameworks/load_path"
require "tmpdir"

# One rule for every place kimera loads or names a test file: run, doctor,
# the isolated child and the printed reproduce command.
RSpec.describe(Kimera::Frameworks::LoadPath) do
  let(:root) { File.realpath(Dir.mktmpdir) }

  after { FileUtils.remove_entry(root) }

  def at(*parts) = File.join(root, *parts).tap { |dir| FileUtils.mkdir_p(dir) }

  def path(files, extra: []) = described_class.new(files, root: root, env: { "KIMERA_LOAD_PATH" => extra.join(":") })

  it "puts the configured folders first, then each file's nearest test or spec folder, then the project's" do
    nested = at("lib", "tool", "test")
    at("test")
    at("spec")
    expect(path([File.join(nested, "a_test.rb")], extra: ["support"]).dirs)
      .to(eq([File.join(root, "support"), nested, File.join(root, "test"), File.join(root, "spec")]))
  end

  it "takes both a test and a spec ancestor, the deepest of each, once" do
    deep = File.join(root, "spec", "unit", "test", "x_test.rb")
    other = File.join(root, "spec", "unit", "test", "y_test.rb")
    expect(path([deep, other]).dirs).to(eq([File.join(root, "spec", "unit", "test"), File.join(root, "spec")]))
  end

  it "leaves out project folders that don't exist and files outside any test folder" do
    expect(path([File.join(root, "lib", "a.rb")]).dirs).to(eq([]))
  end

  it "reads relative files and folders from the root" do
    at("test")
    expect(path(["test/models/a_test.rb"], extra: ["./vendor/x"]).dirs)
      .to(eq([File.join(root, "vendor", "x"), File.join(root, "test")]))
  end

  it "names each folder relative to the root in -I flags" do
    at("test")
    expect(path([File.join(root, "pkg", "spec", "a_spec.rb")], extra: [root]).flags)
      .to(eq(["-I", ".", "-I", "pkg/spec", "-I", "test"]))
  end

  it "reads the configured folders kimera exports, and none when unset", :aggregate_failures do
    configured = { described_class::VARIABLE => "a#{File::PATH_SEPARATOR}b" }
    expect(described_class.new([], root: root, env: configured).dirs)
      .to(eq([File.join(root, "a"), File.join(root, "b")]))
    expect(described_class.new([], root: root, env: {}).dirs).to(eq([]))
  end

  it "defaults to the working directory and the process environment" do
    at("test")
    Dir.chdir(root) { expect(described_class.new([]).dirs).to(include(File.join(root, "test"))) }
  end

  describe "#install" do
    around do |example|
      original = $LOAD_PATH.dup
      example.run
    ensure
      $LOAD_PATH.replace(original)
    end

    it "prepends the folders to $LOAD_PATH in order, once", :aggregate_failures do
      at("test")
      nested = at("lib", "x", "test")
      2.times { path([File.join(nested, "a_test.rb")], extra: ["support"]).install }
      expect($LOAD_PATH.first(3)).to(eq([File.join(root, "support"), nested, File.join(root, "test")]))
      expect($LOAD_PATH.count(nested)).to(eq(1))
    end
  end
end
