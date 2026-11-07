# frozen_string_literal: true

require "English"
require "kimera/registry/builder"
require "kimera/synthesis/project"

RSpec.describe("synthesized baseline") do
  def synthesized(dir)
    root = test_sample
    registry = Kimera::RegistryScan.new(root: root).build(Dir["#{root}/app/**/*.rb"])
    Kimera::Synthesis::Project.new(registry, root: root).write(dir)
    FileUtils.cp_r("#{root}/spec", "#{dir}/spec")
  end

  def green(dir)
    synthesized(dir)
    script = <<~RUBY
      $LOAD_PATH.unshift(#{File.join(test_repository_root, "lib").inspect})
      require "kimera/runtime"
      Kimera::RUNTIME.active = nil
      require "rspec/core"
      Dir.glob(#{dir.inspect} + "/spec/**/*_spec.rb").sort.each { |f| require f }
      exit RSpec::Core::Runner.run([])
    RUBY
    `ruby -e #{script.shellescape} 2>&1`
  end

  it "runs the sample app suite green at active = nil", :aggregate_failures do
    Dir.mktmpdir("kimera-baseline") do |dir|
      output = green(dir)
      expect($CHILD_STATUS.exitstatus).to(eq(0), "baseline suite failed:\n#{output}")
      expect(output).to(include("0 failures"))
    end
  end
end
