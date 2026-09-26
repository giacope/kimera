# frozen_string_literal: true

require_relative "kimera/error"
require_relative "kimera/runtime"
require_relative "kimera/version"

module Kimera
  autoload :MutationPoint, "kimera/registry/mutation_point"
  autoload :Registry, "kimera/registry/registry"
  autoload :RegistryScan, "kimera/registry/builder"
  autoload :Overlay, "kimera/synthesis/overlay"
  autoload :CLI, "kimera/cli"
end
