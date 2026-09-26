# frozen_string_literal: true

require_relative "screen"

module Kimera
  module Report
  end
end

module Kimera::Report::Coloring
  private

  def bold(text)  = colorize(text, "1")
  def red(text)   = colorize(text, "31")
  def green(text) = colorize(text, "32")
  def yellow(text) = colorize(text, "33")

  def colorize(text, code)
    color? ? "\e[#{code}m#{text}\e[0m" : text
  end

  def color? = Kimera::Report::Screen::MODES.key?(@color) ? @color : screen.colored?

  def screen = @_screen ||= Kimera::Report::Screen.for(@io, @color)
end
