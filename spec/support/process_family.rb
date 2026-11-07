# frozen_string_literal: true

module ProcessFamily
  Witness =
    Struct.new(:reader, :holder) do
      def spawn = Process.spawn("sleep", "30", out: holder)

      def outlived?(within: 5)
        holder.close unless holder.closed?
        !(reader.wait_readable(within) && reader.read_nonblock(1, exception: false).nil?)
      ensure
        reader.close
      end
    end

  def witness = Witness.new(*IO.pipe)

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
