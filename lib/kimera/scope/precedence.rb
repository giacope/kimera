# frozen_string_literal: true

Kimera::Config::Precedence =
  Data.define(:cli, :configured) do
    def chosen(default)
      given = Array(cli)
      picked = given.empty? ? Array(configured) : given
      picked.empty? ? default.dup : picked
    end
  end
