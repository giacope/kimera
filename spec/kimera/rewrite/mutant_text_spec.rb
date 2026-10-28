# frozen_string_literal: true

require "tmpdir"
require "kimera/registry/builder"
require "kimera/report/text"
require "kimera/results/run_report"
require "kimera/rewrite/mutant_text"

# R6B6-M3: every report shows the mutant's text. A point's slice is written
# alone when it parses alone (a call forwarding an anonymous `&`, `*`, `**` or
# `...` does, read in a method that forwards them); one that only parses where
# it stands (an element of `%i[]`, a bare list, a call holding a heredoc, a
# `retry`) is written in its file's own tree; when neither can be read, the
# views say so instead of showing a lone `-` line, which reads as a deleted
# statement.
RSpec.describe(Kimera::Rewrite::MutantText) do
  def scanned(code, keys)
    Dir.mktmpdir do |dir|
      path = File.join(dir, "relay.rb")
      File.write(path, code)
      yield(Kimera::RegistryScan.new(operators: Kimera::Operators.build(keys: keys), root: dir).build([path]))
    end
  end

  def texts(code, keys)
    scanned(code, keys) do |registry|
      registry.each.map { |mutant, point| [mutant.label, described_class.new(point, mutant, root: registry.root).text] }
    end
  end

  it "writes a call that forwards an anonymous block from its slice" do
    expect(texts("class Relay\n  def call(value, &) = forward(value, 1, &)\nend\n", %w[argument_drop]))
      .to(eq([["drop arg `value`", "forward(1, &)"], ["drop arg `1`", "forward(value, &)"]]))
  end

  it "writes a word list's element and a bare list's in their file", :aggregate_failures do
    expect(texts("class Relay\n  def kinds = %i[fast slow].size\nend\n", %w[symbol_literal]))
      .to(eq([[":fast => :fast__kimera__", ":fast__kimera__"], [":slow => :slow__kimera__", ":slow__kimera__"]]))
    expect(texts("class Relay\n  def pair(a, b)\n    @a, @b = a, b\n  end\nend\n", %w[element_drop]))
      .to(eq([["drop `a`", "[b]"], ["drop `b`", "[a]"]]))
  end

  def tagged(tag) = "  def #{tag}(x)\n    raw <<~HTML, x\n      <#{tag}>\n    HTML\n  end\n"

  def page = "class Relay\n#{tagged("p")}#{tagged("b")}end\n"

  def again = "class Relay\n  def again(n)\n    work\n  rescue\n    n > 1 ? retry : raise\n  end\nend\n"

  it "writes a call holding a heredoc, and a retry, in their file", :aggregate_failures do
    expect(texts(page, %w[argument_drop]).map(&:last)).to(eq(["raw(x)", %(raw("<p>\\n")), "raw(x)", %(raw("<b>\\n"))]))
    expect(texts(again, %w[conditional]).first.last).to(eq("if true\n      retry\n    else\n      raise\n    end"))
  end

  def kinds = "class Relay\n  def kinds = %i[fast slow].size\nend\n"

  def changed(registry)
    File.write(File.join(registry.root, "relay.rb"), kinds.sub("fast", "fist"))
    registry.each.map { |mutant, point| described_class.new(point, mutant, root: registry.root).text }
  end

  it "is nothing when its file changed where the point was" do
    expect(scanned(kinds, %w[symbol_literal]) { changed(it) }).to(eq([nil, ":slow__kimera__"]))
  end

  def survivor(registry)
    mutant = registry.each.first.first
    result = Kimera::MutantResult.new(mutant_id: mutant.id, status: :survived, file: "relay.rb", duration: 0.1)
    Kimera::RunReport.new(results: [result], registry: registry)
  end

  def shown(registry, report)
    StringIO.new.tap { Kimera::Report::Text.new(registry, io: it, color: false).report(report) }
  end

  it "is nothing when its file is gone, and the report says it could not write the text", :aggregate_failures do
    registry = scanned("class Relay\n  def kinds = %i[fast slow].size\nend\n", %w[symbol_literal]) { it }
    report = survivor(registry)
    expect(report.to_h["results"].first).to(include("original" => "fast", "mutated" => nil))
    expect(shown(registry, report).string).to(include("- fast\n    + #{described_class::UNWRITTEN}\n"))
  end
end
