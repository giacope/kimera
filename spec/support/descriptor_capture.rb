# frozen_string_literal: true

# What the processes the block forks write to descriptor 1, read through a
# pipe. RSpec's to_stdout_from_any_process points descriptor 1 at a Tempfile,
# and Ruby 4.0.7 crashes when a forked child then reopens a second IO on it
# (as a worker's silence! does); a pipe it reopens cleanly. The block must
# reap what it forks, and they must write less than a pipe holds.
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
