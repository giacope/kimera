# frozen_string_literal: true

# What a test that starts a server leaves behind when its process dies
# without teardown: a grandchild. `witness` hands a child the write end of a
# pipe to pass on to what it starts; `outlived?` then tells whether anything
# holding it is still alive (reparented and never reaped, a dead one would
# still answer `kill 0`).
module ProcessFamily
  Witness =
    Struct.new(:reader, :holder) do
      # Starts a grandchild of the caller's that holds the pipe, in the
      # caller's process group.
      def spawn = Process.spawn("sleep", "30", out: holder)

      # Call in the parent once no child that holds the pipe is left to fork.
      def outlived?(within: 5)
        holder.close unless holder.closed?
        !(reader.wait_readable(within) && reader.read_nonblock(1, exception: false).nil?)
      ensure
        reader.close
      end
    end

  def witness = Witness.new(*IO.pipe)

  # A child that leads its own process group, starts a grandchild, and then
  # runs the block (or sleeps). Returns its pid once the grandchild exists.
  def family(witness)
    ready, signal = IO.pipe
    pid =
      fork do
        Process.setpgid(0, 0)
        witness.spawn
        signal.puts
        block_given? ? yield : sleep(30)
        exit!(0)
      end
    signal.close
    ready.gets.tap { ready.close }
    pid
  end
end

RSpec.configure { |config| config.include(ProcessFamily) }
