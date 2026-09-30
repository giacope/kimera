# frozen_string_literal: true

require_relative "lib/kimera/version"

Gem::Specification.new do |spec|
  spec.name = "kimera"
  spec.version = Kimera::VERSION
  spec.authors = ["Giacomo GK"]
  spec.email = ["giaco@hey.com"]
  spec.summary = "Schemata-based mutation testing for Ruby and Rails"
  spec.description = <<~DESC
    Mutation testing for Ruby and Rails built on mutant schemata (Untch, Offutt
    & Harrold, 1993), as popularized by Stryker. All mutants for a file compile
    into one guarded-dispatch program selected at runtime, so there is no
    reparse or reload per mutant. A warm worker pool runs mutants in parallel,
    and diff-driven incremental runs gate CI.
  DESC
  spec.homepage = "https://github.com/giacope/kimera"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.4"
  spec.metadata = {
    "source_code_uri" => spec.homepage,
    "changelog_uri" => "#{spec.homepage}/blob/main/CHANGELOG.md",
    "bug_tracker_uri" => "#{spec.homepage}/issues",
    "rubygems_mfa_required" => "true"
  }
  spec.files = Dir[
    "lib/**/*.rb", "skills/**/*.md", "exe/*", "README.md", "CHANGELOG.md", "LICENSE.txt", ".kimera.yml.example"
  ]
  spec.bindir = "exe"
  spec.executables = ["kimera"]
  spec.require_paths = ["lib"]
  spec.add_dependency("prism", ">= 0.19", "< 2")
  spec.add_dependency("unparser", "~> 0.9.0")
end
