# frozen_string_literal: true

module MyApp
  module Operators
    # Deletes the declaration that protects a column.
    #
    # A survivor means the compliance claim has no test behind it: the suite
    # cannot tell an encrypted column from a plaintext one.
    class EncryptedAttribute < Kimera::Operators::Base
      NAMES = %i[encrypts has_secure_password redact].freeze

      def key = "encrypted_attribute"

      def statement? = true

      def body? = true

      def variants(node, **)
        return unless bare?(node, NAMES)
        deletion(node)
      end
    end
  end
end
