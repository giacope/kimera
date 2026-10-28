# frozen_string_literal: true

require "fileutils"
require "tmpdir"
require "kimera/execution/bundle"

# The Gemfile a mirror's child runs under: the one kimera itself runs under
# (BUNDLE_GEMFILE, an Appraisal-style Gemfile.rails-8.1 or gemfiles/x.gemfile),
# as its copy in the mirror, or the project's own when the lockfile resolved a
# path gem out of the project, which the mirror does not hold.
RSpec.describe(Kimera::Execution::Bundle) do
  def write(dir, files)
    files.each do |path, text|
      FileUtils.mkdir_p(File.dirname(File.join(dir, path)))
      File.write(File.join(dir, path), text)
    end
  end

  def chosen(files, given)
    Dir.mktmpdir do |root|
      Dir.mktmpdir do |mirror|
        [root, mirror].each { |dir| write(dir, files) }
        env = given ? { "BUNDLE_GEMFILE" => given.gsub("ROOT", root) } : {}
        return described_class.new(root, env).gemfile(mirror)&.sub(mirror, "MIRROR")&.sub(root, "ROOT")
      end
    end
  end

  let(:plain) { { "Gemfile" => "gem 'rails', github: 'rails/rails'\n", "Gemfile.ci" => "gem 'rspec'\n" } }

  it "runs under the copy of the Gemfile kimera runs under (R6B5-M4)", :aggregate_failures do
    expect(chosen(plain, "ROOT/Gemfile.ci")).to(eq("MIRROR/Gemfile.ci"))
    expect(chosen(plain, "Gemfile.ci")).to(eq("MIRROR/Gemfile.ci"))
    expect(chosen(plain, "ROOT/Gemfile")).to(eq("MIRROR/Gemfile"))
  end

  it "runs under the project's Gemfile when kimera names none, or one outside the project", :aggregate_failures do
    expect(chosen(plain, nil)).to(eq("MIRROR/Gemfile"))
    expect(chosen(plain, "/elsewhere/Gemfile")).to(eq("MIRROR/Gemfile"))
    expect(chosen(plain, "ROOT")).to(eq("MIRROR/Gemfile"))
    expect(chosen({ "Gemfile.ci" => "" }, nil)).to(be_nil)
  end

  # gemfiles/rails.gemfile's `gemspec path: "../"` resolves to the project,
  # which the mirror holds; `path: "../../engine"` leaves it.
  def nested(remote)
    lock = "PATH\n  remote: #{remote}\n"
    { "gemfiles/rails.gemfile" => "gemspec path: '../'\n", "gemfiles/rails.gemfile.lock" => lock }
  end

  it "runs a path gem resolved in the project from the mirror, one out of it from the project", :aggregate_failures do
    given = "ROOT/gemfiles/rails.gemfile"
    expect(chosen(nested(".."), given)).to(eq("MIRROR/gemfiles/rails.gemfile"))
    expect(chosen(nested("../../engine"), given)).to(eq(given))
    expect(chosen(nested("/opt/engine"), given)).to(eq("MIRROR/gemfiles/rails.gemfile"))
  end
end
