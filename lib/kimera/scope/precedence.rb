# frozen_string_literal: true

class Kimera::Config::Precedence
  def initialize(cli, configured)
    @cli = cli
    @configured = configured
  end

  def chosen(default)
    given = Array(cli)
    picked = given.empty? ? Array(configured) : given
    picked.empty? ? default.dup : picked
  end

  private

  attr_reader :cli, :configured
end
