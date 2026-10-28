# frozen_string_literal: true

module Kimera
end

class Kimera::CLI
end

class Kimera::CLI::Run
end

class Kimera::CLI::Run::NullSelection
  def ids(registry) = registry.index.keys

  def files(found, &) = found

  def narrowed(registry) = registry

  def announce(_io, _selected, _files); end
end
