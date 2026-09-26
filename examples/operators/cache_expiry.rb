# frozen_string_literal: true

module MyApp
  module Operators
    # Drops the cache expiry keyword, so the entry never goes stale.
    #
    # A survivor means the TTL is decorative: no test covers the re-read after
    # expiry, so changing it breaks nothing.
    class CacheExpiry < Kimera::Operators::Base
      NAMES = %i[fetch write].freeze
      KEYS = %w[expires_in expires_at race_condition_ttl].freeze

      class << self
        def key = "cache_expiry"
      end

      def variants(node, **)
        return unless chained?(node, NAMES)
        present(node).map { |key| drop(key) }
      end

      private

      def drop(key)
        Kimera::Operators::Variant.new(
          label: "drop `#{key}:`", directive: directive("kwarg_pair_drop", key: key)
        )
      end

      def present(node)
        keywords(node)&.elements.to_a.filter_map do |assoc|
          next unless assoc.is_a?(Prism::AssocNode)
          key = unescaped(assoc.key)
          key if KEYS.include?(key)
        end
      end
    end
  end
end
