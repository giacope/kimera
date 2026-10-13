# frozen_string_literal: true

module KimeraEval
  # K9: which unparser releases kimera installs with and works on. For each
  # release: does a bundle with kimera's gemspec and that unparser resolve,
  # and do the unit suite and the schemata property specs pass on it. A spec
  # that fails on the newest release too fails for this harness's bundle,
  # not for unparser, so a release is broken only by failures beyond those.
  class UnparserCase < Case
    ID = "K9"
    TITLE = "Works on every unparser release it allows (and allows more than 0.9.x)"
    VERSIONS = %w[0.6.15 0.7.0 0.8.0 0.8.1 0.8.2 0.9.0].freeze
    QUICK = %w[spec/kimera/unparse_spec.rb spec/kimera/unparse_patches_spec.rb spec/kimera/overlay_spec.rb
               spec/kimera/overlay_bake_spec.rb spec/kimera/body_trim_spec.rb spec/kimera/rewrite].freeze
    FULL = %w[spec/kimera spec/property/schemata_spec.rb].freeze

    def call
      runs = VERSIONS.to_h { |version| [version, release(version)] }
      allowed = runs.select { |_version, run| run["resolves"] }
      reference = Array(runs.fetch(VERSIONS.last)["failed"])
      broken = allowed.reject { |_version, run| (Array(run["failed"]) - reference).empty? }
      { "pass" => broken.empty? && allowed.size > 1, "summary" => { "allowed" => allowed.keys.join(" "), "broken" => broken.keys.join(" ") } }
        .merge("runs" => runs)
    end

    private

    def release(version)
      dir = File.join(sandbox.root, "unparser-#{version}")
      FileUtils.mkdir_p(dir)
      File.write(File.join(dir, "Gemfile"), gemfile(version))
      env = { "BUNDLE_GEMFILE" => File.join(dir, "Gemfile") }
      install = Shell.new(env: env, chdir: dir, timeout: 900).run("bundle", "install")
      return { "resolves" => false, "why" => install.output.lines.grep(/unparser|Could not find/).first(2).join } unless install.ok?
      suite(env)
    end

    def gemfile(version)
      <<~RUBY
        source "https://rubygems.org"
        gemspec path: #{checkout.path.dump}
        gem "unparser", "= #{version}"
        gem "rspec", "~> 3.13"
        gem "minitest", "~> 5.20"
        gem "pbt", "~> 0.7"
      RUBY
    end

    def suite(env)
      result = Shell.new(env: env, chdir: checkout.path, timeout: 1800).run("bundle", "exec", "ruby", "bin/spec", *(context.quick? ? QUICK : FULL))
      examples, failures = result.out.scan(/(\d+) examples?, (\d+) failures?/).last
      { "resolves" => true, "ok" => result.ok?, "examples" => examples.to_i, "failures" => failures.to_i }
        .merge("failed" => result.out.lines.grep(%r{^rspec \./}).map { |line| line.split(" # ").first.strip })
    end
  end
end
