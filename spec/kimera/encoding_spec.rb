# frozen_string_literal: true

require "fileutils"
require "kimera/execution/schemata"
require "kimera/registry/builder"
require "kimera/runtime"
require "kimera/synthesis/project"
require "kimera/synthesis/overlay"
require "tmpdir"

# Source must parse even when a C locale makes default_external US-ASCII.
RSpec.describe("non-ASCII source handling") do
  let(:dir) { Dir.mktmpdir }

  after { FileUtils.remove_entry(dir) }

  def test_source_body
    <<~RUBY.encode(Encoding::UTF_8)
      class Widget
        # boundary check — inclusive on the low side
        def big?(a, b)
          a > b
        end
      end
    RUBY
  end

  def test_write_source(path)
    path = File.join(dir, path)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, test_source_body)
    path
  end

  def test_registry_for(path)
    Kimera::RegistryScan.new(root: dir).build([File.join(dir, path)])
  end

  def test_synthesize(path, out)
    test_write_source(path)
    Kimera::Synthesis::Project.new(test_registry_for(path), root: dir).write(out)
  end

  def test_overlay(path)
    test_write_source(path)
    Kimera::Execution::Schemata.new(test_registry_for(path), root: dir).overlay!
  end

  def test_synthesized_module
    source = "def gt(a, b)\n  # note — boundary\n  a > b\nend\n".encode(Encoding::UTF_8)
    registry = Kimera::RegistryScan.new.source(source, file: "u.rb")
    result = Kimera::Overlay.new(registry).synthesize("u.rb", source)
    mod = Module.new
    mod.module_eval(result.source)
    [registry, result, Object.new.extend(mod)]
  end

  def test_expect_toggle(registry, object)
    Kimera::Runtime.active = nil
    expect(object.gt(2, 1)).to(be(true))
    Kimera::Runtime.active = registry.each.find { |m, _p| m.label == "> => <" }.first.id
    expect(object.gt(2, 1)).to(be(false))
  end

  it "builds a registry from a UTF-8 file regardless of default_external", :aggregate_failures do
    test_write_source("widget.rb")
    point = test_registry_for("widget.rb").points.find { |p| p.original_source == "a > b" }
    expect(point).not_to(be_nil)
    expect(point.mutants.map(&:label)).to(contain_exactly("> => >=", "> => <"))
  end

  it "synthesizes a UTF-8 file to a mirror tree without an EncodingError", :aggregate_failures do
    out = File.join(dir, "schemata")
    expect { test_synthesize("widget.rb", out) }.not_to(raise_error)
    expect(File.read(File.join(out, "widget.rb"), encoding: Encoding::UTF_8)).to(include("active?"))
  end

  it "overlays a UTF-8 file in-process without an EncodingError" do
    expect { test_overlay("widget_overlay.rb") }.not_to(raise_error)
  ensure
    # The overlay defines Widget, so stub_const can't clean it up.
    Object.__send__(:remove_const, :Widget) if defined?(Widget)
  end

  # A multibyte char makes whitequark's character offsets diverge from Prism's
  # byte offsets.
  it "synthesizes a working guard for a point after a multibyte character", :aggregate_failures do
    registry, result, object = test_synthesized_module
    expect(result.mutant_ids).not_to(be_empty)
    test_expect_toggle(registry, object)
  ensure
    Kimera::Runtime.reset!
  end

  it "round-trips a registry with non-ASCII source snippets through disk" do
    test_write_source("widget.rb")
    registry = test_registry_for("widget.rb")
    path = File.join(dir, "reg.json").tap { |p| registry.write(p) }
    expect(Kimera::Registry.load(path).count).to(eq(registry.count))
  end
end
