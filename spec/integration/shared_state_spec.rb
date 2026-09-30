# frozen_string_literal: true

# A suite whose tests share a path (thor's spec/sandbox, sinatra's
# test/file.txt) is green in one process and red on several workers. The red
# parallel baseline listed every failing test on one line and said nothing
# about --jobs 1, and doctor --check-baseline, which ran it in one process,
# called it green.
RSpec.describe("a suite that shares a path between tests (end-to-end)") do
  def test_store = <<~RUBY
    require "fileutils"

    class Store
      DIR = "tmp/shared"

      def self.put(value)
        FileUtils.mkdir_p(DIR)
        File.write(File.join(DIR, "entry"), value)
      end

      def self.get = File.read(File.join(DIR, "entry"))

      def self.clear = FileUtils.rm_rf(DIR)
    end
  RUBY

  # Each test writes its own value to the one shared file, waits, and reads
  # it back: on two workers the other writes (or deletes) it meanwhile.
  def test_shared(root)
    FileUtils.mkdir_p(%w[app spec test].map { |dir| File.join(root, dir) })
    File.write(File.join(root, "app", "store.rb"), test_store)
    File.write(File.join(root, ".kimera.yml"), "paths: [app/**/*.rb]\njobs: 2\n")
    %w[a b].each do |name|
      File.write(File.join(root, "spec", "#{name}_spec.rb"), <<~RUBY)
        require_relative "../app/store"

        RSpec.describe("store #{name}") do
          after { Store.clear }

          4.times do |i|
            it("keeps entry \#{i}") do
              Store.put("#{name}\#{i}")
              sleep(0.2)
              expect(Store.get).to(eq("#{name}\#{i}"))
            end
          end
        end
      RUBY
      File.write(File.join(root, "test", "#{name}_test.rb"), <<~RUBY)
        require "minitest/autorun"
        require_relative "../app/store"

        class Store#{name.upcase}Test < Minitest::Test
          def teardown = Store.clear

          4.times do |i|
            define_method("test_keeps_entry_\#{i}") do
              Store.put("#{name}\#{i}")
              sleep(0.2)
              assert_equal("#{name}\#{i}", Store.get)
            end
          end
        end
      RUBY
    end
  end

  def test_doctor(root, config = "")
    File.write(File.join(root, ".kimera.yml"), config, mode: "a")
    doctor = [File.join(test_repo_root, "exe", "kimera"), "doctor", "--check-baseline"]
    command = ["bundle", "exec", "ruby", "-I", File.join(test_repo_root, "lib"), *doctor].shelljoin
    [`cd #{root.shellescape} && BUNDLE_GEMFILE=#{test_gemfile} #{command} 2>&1`, $CHILD_STATUS.exitstatus]
  end

  let(:red) { "! Parallel baseline: red split across 2 processes (jobs: 2), green in one: " }

  it "names --jobs 1 as the check when the baseline is red on two workers, and is green on one", :aggregate_failures do
    Dir.mktmpdir("kimera-shared") do |root|
      test_shared(root)
      test_run(cwd: root, args: ["--jobs", "2", "--no-progress"]) do |output, _report, status|
        expect(status).to(eq(1))
        expect(output).to(match(%r{not green: \d+ tests failed:\n    \./spec/[ab]_spec\.rb\[1:\d\]\n}))
        expect(output).to(
          include("\n  ran on 2 workers: if these pass with --jobs 1, the suite shares state between workers")
        )
      end
      test_run(cwd: root, args: ["--jobs", "1", "--no-progress"]) do |output, report, _status|
        expect(output).not_to(include("not green"))
        expect(report["counts"]["killed"]).to(be_positive)
      end
    end
  end

  it "names --jobs 1 when the coverage pass of an --isolated run is red on two workers" do
    Dir.mktmpdir("kimera-shared") do |root|
      test_shared(root)
      test_run(cwd: root, args: ["--isolated", "--jobs", "2", "--no-progress"]) do |output, _report, status|
        expect([status, output]).to(match([1, a_string_including("ran on 2 workers: if these pass with --jobs 1")]))
      end
    end
  end

  it "has doctor warn that the suite is red split across the configured jobs (RSpec)", :aggregate_failures do
    Dir.mktmpdir("kimera-shared") do |root|
      test_shared(root)
      output, status = test_doctor(root)
      expect(status).to(eq(0))
      expect(output).to(include("✓ Baseline: configured test suite is green\n#{red}"))
      expect(output).to(match(%r{failing tests:\n    \./spec/[ab]_spec\.rb\[1:\d\]\n}))
    end
  end

  it "has doctor warn that the suite is red split across the configured jobs (Minitest)", :aggregate_failures do
    Dir.mktmpdir("kimera-shared") do |root|
      test_shared(root)
      output, status = test_doctor(root, "framework: minitest\ntests: [test/**/*_test.rb]\n")
      expect(status).to(eq(0))
      expect(output).to(include("✓ Baseline: configured test suite is green\n#{red}"))
      expect(output).to(match(/failing tests:\n    Store[AB]Test#test_keeps_entry_\d\n/))
    end
  end

  it "has doctor find the suite green split across processes once each test has its own path" do
    Dir.mktmpdir("kimera-shared") do |root|
      test_shared(root)
      File.write(File.join(root, "app", "store.rb"), test_store.sub("tmp/shared", "tmp/\#{Process.pid}"))
      output, _status = test_doctor(root)
      expect(output).to(include("✓ Parallel baseline: green split across 2 processes too (jobs: 2)"))
    end
  end
end
