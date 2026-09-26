# frozen_string_literal: true

module Kimera
end

class Kimera::Error < StandardError; end

class Kimera::UsageError < Kimera::Error; end
