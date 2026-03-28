defmodule Sigil.MixProjectTest do
  @moduledoc """
  Covers the packet-2 Mix dependency contract for checkpoint streaming.
  """

  use ExUnit.Case, async: true

  test "project dependency list includes grpc for checkpoint streaming" do
    assert_dependency!(Sigil.MixProject.project()[:deps], :grpc, "~> 0.11.5")
  end

  test "project dependency list includes protobuf compatible with grpc" do
    assert_dependency!(Sigil.MixProject.project()[:deps], :protobuf, "~> 0.16.0")
  end

  defp assert_dependency!(deps, app, requirement) do
    dependency =
      Enum.find(deps, fn
        {dep_app, dep_requirement} when dep_app == app and dep_requirement == requirement ->
          true

        {dep_app, dep_requirement, _opts}
        when dep_app == app and dep_requirement == requirement ->
          true

        _other ->
          false
      end)

    assert dependency != nil
    assert {^app, ^requirement} = normalize_dependency_tuple(dependency)
  end

  defp normalize_dependency_tuple({app, requirement}), do: {app, requirement}
  defp normalize_dependency_tuple({app, requirement, _opts}), do: {app, requirement}
end
