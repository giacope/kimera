# frozen_string_literal: true

module MyApp
  module Operators
    # Runs the job inline and sends the mail now instead of enqueueing.
    #
    # A survivor means no test asserts the enqueue: the work runs either way in
    # tests, so a job never backgrounded (or a misconfigured queue) goes unseen.
    class BackgroundDispatch < Kimera::Operators::Base
      SWAPS = { perform_later: :perform_now, deliver_later: :deliver_now }.freeze

      class << self
        def key = "background_dispatch"
      end

      def variants(node, **)
        return unless node.is_a?(Prism::CallNode) && node.receiver
        to = SWAPS[node.name]
        return unless to
        solo("#{node.name} => #{to}", "selector_swap", to: to.to_s)
      end
    end
  end
end
