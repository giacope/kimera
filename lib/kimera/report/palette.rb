# frozen_string_literal: true

require_relative "screen"

module Kimera
  module Report
  end
end

class Kimera::Report::Palette
  def initialize(io, color)
    @io = io
    @color = color
  end

  def bold(text)  = colorize(text, "1")
  def red(text)   = colorize(text, "31")
  def green(text) = colorize(text, "32")
  def yellow(text) = colorize(text, "33")

  private

  def colorize(text, code)
    color? ? "\e[#{code}m#{text}\e[0m" : text
  end

  def color? = @color == true || (@color != false && Kimera::Report::Screen.of(@io, @color).colored?)
end
