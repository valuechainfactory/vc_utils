defmodule VcUtilsTest do
  use ExUnit.Case
  doctest VcUtils

  test "greets the world" do
    assert VcUtils.hello() == :world
  end
end
