# frozen_string_literal: true

# kimera run builds its real harness, but the harness skips the warm pass and
# returns a canned report (or what the block answers), so a spec drives the
# CLI around it in-process. Returns the options each harness was built with.
module HarnessStub
  def stub_harness(results = [], &answer)
    built = []
    allow(Kimera::Execution::Harness).to(receive(:build).and_wrap_original) do |original, **options|
      built << options
      original.call(**options).tap { |harness| idle(harness, results, answer) }
    end
    built
  end

  private

  def idle(harness, results, answer)
    allow(harness).to(receive(:warm!))
    return allow(harness).to(receive(:run, &answer)) if answer
    allow(harness).to(receive(:run).and_return(Kimera::RunReport.new(results: results)))
  end
end

RSpec.configure { |config| config.include(HarnessStub) }
