# frozen_string_literal: true

require "English"
require "kimera/registry/builder"
require "kimera/synthesis/project"

RSpec.describe("synthesized baseline") do
  it "runs the sample app suite green at active = nil", :aggregate_failures do
    root = test_sample
    lib = File.join(test_repo_root, "lib")

    Dir.mktmpdir("kimera-baseline") do |dir|
      registry = Kimera::RegistryScan.new(root: root).build(Dir["#{root}/app/**/*.rb"])
      Kimera::Synthesis::Project.new(registry, root: root).write(dir)

      # So require_relative resolves to the synthesized app files.
      FileUtils.cp_r("#{root}/spec", "#{dir}/spec")

      script = <<~RUBY
        $LOAD_PATH.unshift(#{lib.inspect})
        require "kimera/runtime"
        Kimera::Runtime.active = nil
        require "rspec/core"
        Dir.glob(#{dir.inspect} + "/spec/**/*_spec.rb").sort.each { |f| require f }
        exit RSpec::Core::Runner.run([])
      RUBY

      output = `ruby -e #{script.shellescape} 2>&1`
      expect($CHILD_STATUS.exitstatus).to(eq(0), "baseline suite failed:\n#{output}")
      expect(output).to(include("0 failures"))
    end
  end
end
