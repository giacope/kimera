# frozen_string_literal: true

require "fileutils"
require "kimera/execution/macro_lambdas"
require "kimera/registry/builder"
require "tmpdir"

using PointFields

RSpec.describe(Kimera::Execution::MacroLambdas) do
  let(:source) do
    <<~RUBY
      class MacroLambdaBoost
        belongs_to :booster, default: -> { Current.user }
        scope :ordered, -> { order(:created_at) }
        LIMIT = -> { size > 10 }

        def score(a, b)
          check = -> { a > b }
          check.call
        end

        def rank(a, b) = run(-> { a < b })
      end
    RUBY
  end

  let(:dir) { Dir.mktmpdir }
  let(:file) { File.join(dir, "boost.rb").tap { |path| File.write(path, source) } }
  let(:registry) { Kimera::RegistryScan.new(root: dir).build([file]) }

  def inside
    yield
  ensure
    FileUtils.remove_entry(dir)
  end

  def point(text) = registry.to_a.find { |found| found.original_source == text }

  it "sends an uncovered lambda a class-body macro is handed to the isolated tier", :aggregate_failures do
    inside do
      described_class.new(registry, dir).quarantine!({})
      expect(PointVerdict.new(point("Current.user"))).to(have_attributes(safe?: false, hazard: Kimera::Reason::MACRO_REASON))
      expect(point("Current.user").reasons(Kimera::Reason.unreloadable).empty?).to(be(false))
    end
  end

  def covered
    [point("Current.user"), point("order(:created_at)")].tap do |booster, ordered|
      described_class.new(registry, dir).quarantine!({ booster.ids.first => ["t1"], ordered.ids.first.to_s => ["t1"] })
    end
  end

  it "judges a macro's lambda a test covers warm, and a survivor again in a fresh mirror", :aggregate_failures do
    inside do
      pair = covered
      expect(pair.map(&:safe?)).to(eq([true, true]))
      expect(pair.map { PointVerdict.new(it).revisit }).to(eq([Kimera::Reason::MACRO_KEPT] * 2))
    end
  end

  it "leaves lambdas no class-body macro is handed: a constant's, and those in a method", :aggregate_failures do
    inside do
      described_class.new(registry, dir).quarantine!({})
      expect([point("size > 10"), point("a > b"), point("a < b")].map(&:safe?)).to(eq([true, true, true]))
      expect([point("size > 10"), point("a > b"), point("a < b")].map { PointVerdict.new(it).revisit })
        .to(eq([nil] * 3))
    end
  end

  def marked
    point("Current.user").mark!(Kimera::Reason.unsafe(Kimera::Reason::LOAD_REASON))
    point("order(:created_at)").mark!(Kimera::Reason.revisit(Kimera::Reason::BOOT_REASON))
    described_class.new(registry, dir).quarantine!({})
  end

  it "leaves a point sent elsewhere already, for a reason or a revisit of its own", :aggregate_failures do
    inside do
      marked
      expect(point("Current.user").reasons(Kimera::Reason.unsafety).first).to(eq(Kimera::Reason::LOAD_REASON))
      expect(point("order(:created_at)").safe?).to(be(true))
    end
  end

  it "leaves the lambdas of a file guarded as it loaded" do
    inside do
      described_class.new(registry, dir, ->(woven) { woven == "boost.rb" }).quarantine!({})
      expect(point("Current.user").safe?).to(be(true))
    end
  end

  def gone = registry.tap { File.delete(file) }

  it "leaves the points of a file that is gone" do
    inside do
      described_class.new(gone, dir).quarantine!({})
      expect(point("Current.user").safe?).to(be(true))
    end
  end
end
