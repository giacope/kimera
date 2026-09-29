# frozen_string_literal: true

require "fileutils"
require "kimera/registry/mutation_point"
require "kimera/synthesis/body_trim"
require "tmpdir"

# A warm overlay evaluates a file that already ran, so only code carrying a
# live mutant has to run again. Re-running the rest of a class body would
# redeclare DSL state (a class_attribute default, a registry entry, a
# pre_check) on top of what the first load left.
RSpec.describe(Kimera::BodyTrim) do
  def live(source, snippets)
    snippets.map { |text| Kimera::Location.new(start_offset: source.b.index(text.b), span: text.bytesize) }
  end

  def trim(source, *snippets) = described_class.trimmed(source, live(source, snippets))

  def lines(text) = text.lines.map(&:strip).reject(&:empty?)

  # The statements left standing, one per line.
  def kept(source, *snippets) = lines(trim(source, *snippets))

  it "blanks class-body statements without a live mutant, in place", :aggregate_failures do
    source = <<~RUBY
      class Widget < Base
        include Trackable
        track :name,
              :size
        def label(size) = size > 1
        def plain = 1
      end
    RUBY
    trimmed = trim(source, "size > 1")
    expect(lines(trimmed)).to(eq(["class Widget < Base", "def label(size) = size > 1", "end"]))
    expect(trimmed.bytesize).to(eq(source.bytesize))
    expect(trimmed.lines.size).to(eq(source.lines.size))
    expect(trimmed.index("size > 1")).to(eq(source.index("size > 1")))
  end

  it "keeps a UTF-8 file UTF-8, blanking multibyte text byte for byte", :aggregate_failures do
    source = "class Café\n  NAME = \"crème\"\n  def ok?(n) = n > 1\nend\n"
    trimmed = trim(source, "n > 1")
    expect(trimmed.encoding).to(eq(Encoding::UTF_8))
    expect(trimmed.bytesize).to(eq(source.bytesize))
    expect(lines(trimmed)).to(eq(["class Café", "def ok?(n) = n > 1", "end"]))
  end

  it "keeps visibility, requires and local variables, which the kept code relies on" do
    source = <<~RUBY
      require "set"
      require_relative "helper"
      module Tools
        module_function
        limit = 3
        count ||= 0
        count += 1
        count &&= 2
        one, @two = 1, 2
        @three, @four = 3, 4
        def big?(n) = n > 3
        private_class_method :new
        public_class_method :new
        protected
        public
        private :big?
        private def small?(n) = n < 0
        private def plain = 1
      end
    RUBY
    expect(kept(source, "n > 3", "n < 0")).to(eq(lines(source) - ["@three, @four = 3, 4", "private def plain = 1"]))
  end

  # Sinatra::Base declares `ruby2_keywords :new if respond_to?(:ruby2_keywords, true)`.
  # Blanked, the re-evaluated `new(*args)` stops passing keywords through.
  it "keeps ruby2_keywords, also under a modifier condition, and a guarded directive" do
    source = <<~RUBY
      class App
        def self.new(*args, &block) = args.size > 1
        ruby2_keywords :new if respond_to?(:ruby2_keywords, true)
        ruby2_keywords(:use)
        private :helper unless $DEBUG
        track :name if enabled?
        if ok? then private :x else skip end
      end
    RUBY
    dropped = ["track :name if enabled?", "if ok? then private :x else skip end"]
    expect(kept(source, "args.size > 1")).to(eq(lines(source) - dropped))
  end

  describe "aliases" do
    let(:source) do
      <<~RUBY
        class Named
          alias_method :original, :name
          def name = @first && @last
          alias to_s name
          alias_method :to_str, :name
          alias_method :label, "name"
          alias_method :title, :plain
          alias other plain
          alias_method :dynamic, target
          def plain = 1
        end
      RUBY
    end

    it "keeps an alias only when it follows a live definition of its target" do
      dropped = [
        "alias_method :original, :name", "alias_method :title, :plain", "alias other plain",
        "alias_method :dynamic, target", "def plain = 1"
      ]
      expect(kept(source, "@first && @last")).to(eq(lines(source) - dropped))
    end
  end

  describe "nesting" do
    let(:source) do
      <<~RUBY
        module Outer
          VERSION = "1"
          class Inner < Base
            has_many :rows
            class << self
              attr_accessor :registry
              def build(n) = n > 0
            end
          end
          class Idle
            def quiet = 1
          end
        end
      RUBY
    end

    it "descends into the classes, modules and singleton classes that carry live code" do
      expect(kept(source, "n > 0")).to(eq(lines(<<~RUBY)))
        module Outer
        class Inner < Base
        class << self
        def build(n) = n > 0
        end
        end
        end
      RUBY
    end
  end

  describe "blocks" do
    let(:source) do
      <<~RUBY
        module Trackable
          extend ActiveSupport::Concern
          included do
            class_attribute :tracked, default: []
            scope :recent, -> { where(age > 1) }
          end
          class_methods do
            def track(*names) = names.size > 1
            def plain = 1
          end
          before_save do
            normalize
            self.rank = -> { rank > 2 }.call
          end
          validates :name, if: -> { name != "x" }
          Host.class_eval do
            attr_reader :seen
            def seen?(n) = n > 0
          end
        end
      RUBY
    end

    it "descends into declaration blocks and keeps any other block whole" do
      live = ["age > 1", "names.size > 1", "rank > 2", 'name != "x"', "n > 0"]
      dropped = [
        "extend ActiveSupport::Concern", "class_attribute :tracked, default: []", "def plain = 1", "attr_reader :seen"
      ]
      expect(kept(source, *live)).to(eq(lines(source) - dropped))
    end
  end

  describe "constant blocks" do
    let(:source) do
      <<~RUBY
        Point = Struct.new(:x) do
          include Comparable
          def big? = x > 10
        end
        Shapes::Box = Data.define(:w) do
          def wide? = w > 2
        end
        Anon = Class.new(Base) do
          self.table_name = "anons"
          def odd?(n) = n > 1
        end
        Mixin = Module.new do
          extend self
          def on?(n) = n < 1
        end
        Built = Builder.build do
          setting :x
          def ok?(n) = n >= 1
        end
        HANDLER = ->(n) { n <= 1 }
      RUBY
    end

    it "descends into Struct, Data, Class and Module blocks assigned to a constant" do
      live = ["x > 10", "w > 2", "n > 1", "n < 1", "n >= 1", "n <= 1"]
      dropped = ["include Comparable", 'self.table_name = "anons"', "extend self"]
      expect(kept(source, *live)).to(eq(lines(source) - dropped))
    end
  end

  it "blanks a heredoc's body along with its statement" do
    source = <<~RUBY
      class Doc
        DESCRIPTION = <<~TEXT.strip
          text that is not code
        TEXT
        def long?(n) = n > 3
      end
    RUBY
    expect(kept(source, "n > 3")).to(eq(["class Doc", "def long?(n) = n > 3", "end"]))
  end

  it "counts a mutant ending where its statement ends as live, and one reaching past it as not" do
    source = "class Pair\n  track :a\n  track :b\nend\n"
    reaching = Kimera::Location.new(start_offset: source.index(":b"), span: ":b\n".bytesize)
    trimmed = described_class.trimmed(source, [*live(source, [":a"]), reaching])
    expect(lines(trimmed)).to(eq(["class Pair", "track :a", "end"]))
  end

  it "keeps the source whole when blanking would leave it unparseable" do
    # Blanking the second heredoc's body from the end of its line would take
    # the first heredoc's terminator with it.
    source = "class Mixed\n  def size = <<~TEXT.size > 1; register(<<~NOTE)\n    text\n  TEXT\n    note\n  NOTE\nend\n"
    expect(trim(source, "<<~TEXT.size > 1")).to(eq(source))
  end

  describe ".trim" do
    let(:dir) { File.realpath(Dir.mktmpdir) }
    let(:source) { "class Trimmed\n  include Comparable\n  def ok?(n) = n > 1\nend\n" }
    let(:locations) { live(source, ["n > 1"]) }

    after { FileUtils.remove_entry(dir) }

    def write(name)
      File.join(dir, name).tap { |path| File.write(path, "# #{name}\n") }
    end

    it "trims a file that has been required, and leaves one nothing required whole", :aggregate_failures do
      path = write("required.rb")
      require(path)
      expect(described_class.trim(path, source, locations)).not_to(include("Comparable"))
      expect(described_class.trim(write("never.rb"), source, locations)).to(eq(source))
    end

    it "finds a required file under its real path or the path it was required by", :aggregate_failures do
      real = write("real.rb")
      linked = write("linked.rb")
      FileUtils.ln_s(dir, File.join(dir, "link"))
      require(real)
      require(File.join(dir, "link", "linked.rb"))
      expect(described_class.loaded?(File.join(dir, "link", "real.rb"))).to(be(true))
      expect(described_class.loaded?(File.join(dir, "link", "linked.rb"))).to(be(true))
      expect(described_class.loaded?(linked)).to(be(false))
      expect(described_class.loaded?(File.join(dir, "missing.rb"))).to(be(false))
    end
  end
end
