defmodule KdefTest do
  use ExUnit.Case
  doctest Kdef

  test "greets the world" do
    assert Kdef.hello() == :world
  end
end
