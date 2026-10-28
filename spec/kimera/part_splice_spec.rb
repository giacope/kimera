# frozen_string_literal: true

require "kimera/synthesis/part_splice"

# R6B3-M4: a mutant of a part of a heredoc, or of a string spanning lines, is
# written in the literal's own text, every line where it was: what the literal
# reads is the original with that part's text replaced.
RSpec.describe(Kimera::PartSplice, :aggregate_failures) do
  def literal(source) = Prism.parse(source).value.statements.body.first.value

  def read(source)
    parts = literal(source).parts
    parts.sum("") { |part| part.type == :string_node ? part.unescaped : part.location.slice }
  end

  def spliced(source, index, value)
    node = literal(source)
    part = node.parts[index]
    from, to, text = described_class.new(node).edit(part, part.copy(unescaped: value))
    source.byteslice(0, from) + text + source.byteslice(to..)
  end

  def expected(source, index, value)
    parts = literal(source).parts
    parts.each_with_index.sum("") do |part, at|
      next value if at == index
      part.type == :string_node ? part.unescaped : part.location.slice
    end
  end

  def kept?(source, index, value)
    written = spliced(source, index, value)
    [read(written), written.lines.size] == [expected(source, index, value), source.lines.size]
  end

  it "writes a part of a squiggly heredoc at its indentation, its line break as a continuation" do
    source = "x = <<~T\n  a \#{b}\n    c\n\n  d\nT\n"
    expect([0, 2, 3].map { |index| kept?(source, index, "new\tvalue \"\#{q}\"") }).to(all(be(true)))
    expect([2, 3, 4].map { |index| kept?(source, index, "") }).to(all(be(true)))
  end

  it "empties the start of a line up to its interpolation in place" do
    expect(kept?("x = <<~T\n  a\n  b \#{c}\n  d\nT\n", 1, "")).to(be(true))
  end

  it "empties a line in place, and only the last one by continuing the line before it", :aggregate_failures do
    source = "x = <<~T\n  a\n  b \#{c}\n  d\n  e\nT\n"
    expect(spliced(source, 4, "")).to(eq("x = <<~T\n  a\n  b \#{c}\n  \\\n  e\nT\n"))
    expect(spliced(source, 5, "")).to(eq("x = <<~T\n  a\n  b \#{c}\n  d\\\n\nT\n"))
    expect(spliced(source, 5, "z")).to(eq("x = <<~T\n  a\n  b \#{c}\n  d\n  z\\\nT\n"))
  end

  it "empties a heredoc's first line in place" do
    expect(kept?("x = <<~T\n  a\n  \#{b}\n  c\nT\n", 0, "")).to(be(true))
    expect(spliced("x = <<~T\n  a\n  \#{b}\n  c\nT\n", 0, "")).to(start_with("x = <<~T\n  \\\n"))
  end

  it "empties a heredoc's last line by continuing the line before it, blank or not" do
    expect(kept?("x = <<~T\n  a \#{b}\n  c\nT\n", 3, "")).to(be(true))
    expect(kept?("x = <<~T\n  a \#{b}\n\n  c\nT\n", 4, "")).to(be(true))
    expect(spliced("x = <<~T\n  a \#{b}\n\n  c\nT\n", 4, "")).to(eq("x = <<~T\n  a \#{b}\n  \\\n\nT\n"))
  end

  it "writes a part of a dash heredoc or a %{} string over all its lines" do
    expect(kept?("x = <<-T\n  a \#{b}\n  c\n  d\n  e \#{f}\nT\n", 2, "z")).to(be(true))
    expect(kept?("x = <<-T\n  a \#{b}\n  c\n  d\n  e \#{f}\nT\n", 0, "z")).to(be(true))
    expect(kept?("x = %{\n  a \#{b}\n}\n", 0, "q")).to(be(true))
    expect(kept?("x = \"a\#{b}c\"\n", 0, "y")).to(be(true))
  end

  it "counts a line that opens with an interpolation in a squiggly heredoc's indentation" do
    expect(kept?("x = <<~T\n  a\n\#{b}\n  c\n  e\nT\n", 3, "d")).to(be(true))
    expect(kept?("x = <<~T\n  a \#{b}\n\#{c}\n  d\nT\n", 5, "")).to(be(true))
  end

  it "writes nothing for a part of a heredoc that takes its text as written" do
    node = literal("x = <<~'T'\n  a\n  b\nT\n")
    expect(described_class.new(node).edit(node.parts.first, node.parts.first.copy(unescaped: ""))).to(be_nil)
  end
end
