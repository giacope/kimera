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
  def test_shared(root, store)
    FileUtils.mkdir_p(%w[app spec test].map { |dir| File.join(root, dir) })
    File.write(File.join(root, "app", "store.rb"), store)
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
    doctor = [File.join(test_repository_root, "exe", "kimera"), "doctor", "--check-baseline"]
    command = ["bundle", "exec", "ruby", "-I", File.join(test_repository_root, "lib"), *doctor].shelljoin
    `cd #{root.shellescape} && BUNDLE_GEMFILE=#{test_gemfile} #{command} 2>&1`
      .force_encoding(Encoding::UTF_8).then { |text| [text, $CHILD_STATUS.exitstatus] }
  end

  def shared_run(*flags)
    Dir.mktmpdir("kimera-shared") do |root|
      test_shared(root, test_store)
      test_outcome(cwd: root, arguments: [*flags, "--no-progress"])
    end
  end

  def doctored(config = "", store: test_store)
    Dir.mktmpdir("kimera-shared") do |root|
      test_shared(root, store)
      test_doctor(root, config)
    end
  end

  def parallel_hint
    "\n  ran on 2 workers: if the reproduce command above fails too, the tests are red on their own; " \
      "if it passes and --jobs 1 is green, the suite shares state between workers"
  end

  let(:red) { "! Parallel baseline: red split across 2 processes (jobs: 2), green in one: " }

  it "names --jobs 1 as the check when the baseline is red on two workers", :aggregate_failures do
    run = shared_run("--jobs", "2")
    expect(run.status).to(eq(1))
    expect(run.output).to(
      match(%r{not green: \d+ tests failed:\n    \./spec/[ab]_spec\.rb\[1:\d\]\n}).and(include(parallel_hint))
    )
  end

  it "is green on one worker", :aggregate_failures do
    run = shared_run("--jobs", "1")
    expect(run.output).not_to(include("not green"))
    expect(run.counts["killed"]).to(be_positive)
  end

  it "names --jobs 1 when the coverage pass of an --isolated run is red on two workers" do
    run = shared_run("--isolated", "--jobs", "2")
    expect([run.status, run.output]).to(
      match([1, a_string_including("ran on 2 workers: if the reproduce command above fails too")])
    )
  end

  it "has doctor warn that the suite is red split across the configured jobs (RSpec)", :aggregate_failures do
    output, status = doctored
    expect(status).to(eq(0))
    expect(output).to(
      include("✓ Baseline: configured test suite is green\n#{red}")
        .and(match(%r{failing tests:\n    \./spec/[ab]_spec\.rb\[1:\d\]\n}))
    )
  end

  it "has doctor warn that the suite is red split across the configured jobs (Minitest)", :aggregate_failures do
    output, status = doctored("framework: minitest\ntests: [test/**/*_test.rb]\n")
    expect(status).to(eq(0))
    expect(output).to(
      include("✓ Baseline: configured test suite is green\n#{red}")
        .and(match(/failing tests:\n    Store[AB]Test#test_keeps_entry_\d\n/))
    )
  end

  it "has doctor find the suite green split across processes once each test has its own path" do
    output, _status = doctored(store: test_store.sub("tmp/shared", "tmp/\#{Process.pid}"))
    expect(output).to(include("✓ Parallel baseline: green split across 2 processes too (jobs: 2; one sample"))
  end
end
