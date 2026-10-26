# frozen_string_literal: true

require "fileutils"

module Kimera
  module Execution
  end
end

class Kimera::Execution::DatabaseCopies; end

class Kimera::Execution::DatabaseCopies::Sqlite
  SIDECARS = %w[-wal -shm -journal].freeze

  def initialize(config)
    @config = config
  end

  def copy(name)
    remove(name)
    from = path(@config.database)
    to = path(name)
    FileUtils.cp(from, to)
    FileUtils.cp("#{from}-wal", "#{to}-wal") if File.file?("#{from}-wal")
  end

  def exist?(name) = File.file?(path(name))

  def remove(name)
    file = path(name)
    FileUtils.rm_f([file, *SIDECARS.map { |suffix| "#{file}#{suffix}" }])
  end

  private

  def path(name) = File.expand_path(name, (Rails.root if defined?(Rails.root)) || Dir.pwd)
end
