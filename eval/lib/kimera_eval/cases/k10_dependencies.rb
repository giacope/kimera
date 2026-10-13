# frozen_string_literal: true

require "bundler"

module KimeraEval
  # K10: the README names every gem kimera installs at runtime: the closure
  # of the gemspec's runtime dependencies, as Bundler resolves it.
  class DependenciesCase < Case
    ID = "K10"
    TITLE = "README names the whole runtime dependency closure"

    def call
      closure = resolve
      readme = File.read(File.join(checkout.path, "README.md"))
      missing = closure.reject { |name| readme.match?(/\b#{Regexp.escape(name)}\b/i) }
      { "pass" => missing.empty?, "summary" => { "closure" => closure.size, "unnamed" => missing.join(" ") } }
        .merge("closure" => closure)
    end

    private

    def resolve
      dir = File.join(sandbox.root, "closure")
      FileUtils.mkdir_p(dir)
      File.write(File.join(dir, "Gemfile"), "source 'https://rubygems.org'\ngem 'kimera', path: #{checkout.path.dump}")
      Shell.new(env: { "BUNDLE_GEMFILE" => File.join(dir, "Gemfile") }, chdir: dir).run("bundle", "lock")
      walk(Bundler::LockfileParser.new(File.read(File.join(dir, "Gemfile.lock"))).specs)
    end

    def walk(specs)
      index = specs.to_h { |spec| [spec.name, spec] }
      found = index.fetch("kimera").dependencies.map(&:name)
      found.each { |name| found.concat(index.fetch(name).dependencies.map(&:name) - found) }
      found.sort
    end
  end
end
