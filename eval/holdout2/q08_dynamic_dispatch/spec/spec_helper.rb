# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "order_flow"

RSpec.configure do |config|
  config.disable_monkey_patching!
end
