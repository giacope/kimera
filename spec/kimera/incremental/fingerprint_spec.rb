# frozen_string_literal: true

require "fileutils"
require "kimera/incremental/fingerprint"
require "tmpdir"

RSpec.describe(Kimera::Incremental::Fingerprint) do
  let(:root) { Dir.mktmpdir("kimera-fingerprint") }
  let(:options) { { tests: ["spec/**/*_spec.rb"], operators: %w[comparison], jobs: 2 } }

  before do
    {
      "lib/a.rb" => "1", "spec/a_spec.rb" => "2", "spec/support/h.rb" => "3", "doc/x.md" => "4",
      ".rspec" => "5", "config/routes.rb" => "6", "db/schema.rb" => "7", "spec/lib/a.rb" => "8"
    }.each { |path, body| write(path, body) }
  end

  after { FileUtils.remove_entry(root) }

  def write(path, body)
    FileUtils.mkdir_p(File.dirname(File.join(root, path)))
    File.write(File.join(root, path), body)
  end

  def git(*) = system("git", "-C", root, *, out: File::NULL, err: File::NULL)

  def fingerprint(sources: ["lib/a.rb"], **over)
    described_class.new(root: root, options: options.merge(over), sources: sources).to_h
  end

  def digest(body) = Digest::SHA256.hexdigest(body)

  it "digests the sources it is given, by path" do
    expect(fingerprint["sources"]).to(eq("lib/a.rb" => digest("1")))
  end

  it "digests the tests, their folder, .rspec and a Rails app's config and schema, but no source or document" do
    expect(fingerprint(sources: ["lib/a.rb", "spec/lib/a.rb"])["files"].keys).to(
      eq(%w[.rspec config/routes.rb db/schema.rb spec/a_spec.rb spec/support/h.rb])
    )
  end

  it "names Ruby" do
    expect(fingerprint["ruby"]).to(eq("#{RUBY_ENGINE} #{RUBY_ENGINE_VERSION} #{RUBY_PLATFORM}"))
  end

  it "changes its settings digest with a setting that picks the tests, but not with one that does not" do
    settings = [fingerprint(operators: %w[negation]), fingerprint(jobs: 4)].map { |found| found["settings"] }
    expect(settings.map { |each| each == fingerprint["settings"] }).to(eq([false, true]))
  end

  it "has no commit outside git" do
    expect(fingerprint["commit"]).to(be_nil)
  end

  context "with the project in git" do
    before do
      git("init", "-q")
      write(".gitignore", "spec/examples.txt\n")
      write("spec/examples.txt", "status")
      git("add", "-A")
      git("-c", "user.email=a@b.c", "-c", "user.name=t", "commit", "-q", "-m", "initial")
    end

    it "names the commit" do
      expect(fingerprint["commit"]).to(match(/\A\h{40}\z/))
    end

    it "leaves out the files git ignores" do
      expect(fingerprint["files"]).not_to(have_key("spec/examples.txt"))
    end
  end
end
