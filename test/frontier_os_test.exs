defmodule FrontierOSTest do
  use ExUnit.Case, async: true
  doctest FrontierOS

  test "greets the world" do
    assert FrontierOS.hello() == :world
  end
end
