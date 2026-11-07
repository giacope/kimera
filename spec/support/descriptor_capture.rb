# frozen_string_literal: true

module DescriptorCapture
  def descriptor_one
    reader, writer = IO.pipe
    saved = $stdout.dup
    $stdout.reopen(writer)
    yield
    $stdout.reopen(saved)
    writer.close
    reader.read
  ensure
    $stdout.reopen(saved)
    [reader, writer, saved].each { |io| io.close unless io.closed? }
  end
end

RSpec.configure { |config| config.include(DescriptorCapture) }
