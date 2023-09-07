defmodule VCUtilsTest do
  use ExUnit.Case
  doctest VCUtils

  test "greets the world" do
    assert VCUtils.hello() == :world
  end
end
