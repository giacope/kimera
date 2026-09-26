# frozen_string_literal: true

# Entry point for kimera's `require:` config key. Point at it with:
#
#   # .kimera.yml
#   require:
#     - examples/operators/kimera_plugin.rb
#   operators: [all]        # or: [comparison, custom] to run built-ins plus these
#
# or `kimera run --require examples/operators/kimera_plugin.rb --operators custom`.
require "kimera/operators"

require_relative "authorization"
require_relative "background_dispatch"
require_relative "bang_call"
require_relative "cache_expiry"
require_relative "encrypted_attribute"
require_relative "http_status"
require_relative "money_rounding"

module MyApp
  module Operators
    ALL = [
      Authorization,
      BackgroundDispatch,
      BangCall,
      CacheExpiry,
      EncryptedAttribute,
      HttpStatus,
      MoneyRounding
    ].freeze
  end
end

Kimera::Operators.register(MyApp::Operators::ALL)
