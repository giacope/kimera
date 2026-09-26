# frozen_string_literal: true

module Kimera
  module OperatorProtocol
    TYPE = "type"
    INDEX = "index"
    STATEMENT_DELETION = "statement_deletion"
    Variant = Struct.new(:label, :directive, keyword_init: true)
  end
end
