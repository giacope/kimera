# frozen_string_literal: true

# Every test runs, in the baseline and for each mutant, in a process forked
# from one no test has run in. So a cache another file fills, a test that
# hides a later caller behind that cache, and a registry later tests add to
# all read as they would in a fresh `rspec` run.
RSpec.describe("kimera run on a suite whose state outlives a test (end-to-end)", :aggregate_failures) do
  def files = {
    "app/rate.rb" => "class Rate\n  def self.compute(x)\n    x > 10 ? 2 : 1\n  end\nend\n",
    "app/cache.rb" => <<~RUBY,
      require_relative "rate"

      class Cache
        def self.get(x)
          (@store ||= {})[x] ||= Rate.compute(x)
        end
      end
    RUBY
    "app/plugins.rb" => <<~RUBY,
      module Plugins
        Plugin = Struct.new(:name, :enabled)
        @all = [Plugin.new("core", true)]

        def self.register(name, enabled:)
          @all << Plugin.new(name, enabled)
        end

        def self.names
          @all.filter_map { |plugin| plugin.name if plugin.enabled }
        end
      end
    RUBY
    "spec/a_cache_spec.rb" => <<~RUBY,
      require_relative "../app/cache"

      RSpec.describe Cache do
        it("warms itself") { [10, 11].each { |x| Cache.get(x) } }
        it("charges the high rate above 10") { expect(Cache.get(11)).to eq(2) }
        it("charges the low rate at 10") { expect(Cache.get(10)).to eq(1) }
      end
    RUBY
    "spec/b_plugins_spec.rb" => <<~RUBY,
      require_relative "../app/plugins"

      RSpec.describe Plugins do
        it("lists the enabled plugins") { expect(Plugins.names).to eq(["core"]) }
      end
    RUBY
    "spec/c_register_spec.rb" => <<~RUBY
      require_relative "../app/plugins"

      RSpec.describe Plugins do
        it("registers a disabled plugin") { expect(Plugins.register("legacy", enabled: false).size).to eq(2) }
      end
    RUBY
  }

  def verdicts(report) = report.fetch("results").to_h { |row| ["#{row["file"]} #{row["label"]}", row["status"]] }

  def ran(jobs)
    test_tree(files, "kimera-state") do |root|
      test_outcome(cwd: root, arguments: ["--jobs", jobs.to_s, "--no-progress"])
    end
  end

  # The verdicts that tell a fresh run of the suite from a stale one, and the leaks.
  def telling(run)
    plugins = verdicts(run.report).values_at("app/plugins.rb condition => true", "app/plugins.rb condition => false")
    [run.statuses("app/rate.rb"), plugins, run.report.fetch("leaks")]
  end

  [1, 2].each do |jobs|
    it "judges each mutant as a fresh run of the suite would, at --jobs #{jobs}" do
      run = ran(jobs)
      expect(telling(run)).to(eq([["killed"], %w[survived killed], []]), run.output)
    end
  end
end
