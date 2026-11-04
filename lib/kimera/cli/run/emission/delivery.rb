# frozen_string_literal: true

class Kimera::CLI::Run::Emission; end

class Kimera::CLI::Run::Emission::Delivery
  def initialize(page, copies, format, metadata)
    @page = page
    @copies = copies
    @format = format
    @metadata = metadata
  end

  def deliver(report, registry, emission)
    text = @page.text(report, registry, emission)
    document = report.annotate(run: @metadata).to_h
    emission.present(text, @format, document)
    @copies.keep(text, document)
  end
end
