defmodule Alfred.NamesTest do
  use ExUnit.Case, async: true
  use Should

  @moduletag alfred: true, alfred_names: true

  setup [:opts_add, :register_add]

  # defmacro assert_registered_name(ctx, :ok_pid) do
  #   quote bind_quoted: [ctx: ctx] do
  #     assert %{registered_name: %{name: <<_::binary>> = name, pid: {:ok, pid}}} = ctx
  #     assert Process.alive?(pid)
  #
  #     name
  #   end
  # end
  #
  # defmacro assert_registered_name(ctx, :ok) do
  #   quote bind_quoted: [ctx: ctx] do
  #     assert %{registered_name: %{name: <<_::binary>> = name, pid: :ok}} = ctx
  #     refute Alfred.Name.missing?(name)
  #
  #     name
  #   end
  # end

  describe "Alfred.Names.registered/0" do
    @tag register_add: [count: 200]
    test "all registered names", %{registered_names: names} do
      names = Enum.sort(names)

      extra = names -- Alfred.Names.registered()

      assert [] == extra
    end
  end

  def opts_add(ctx) do
    opts_default = [callback: fn _what, _opts -> self() end]

    case ctx do
      %{opts_add: opts} -> %{opts: Keyword.merge(opts_default, opts)}
      _ -> %{opts: opts_default}
    end
  end

  def register_add(%{register_add: [{:count, count}], opts: opts}) do
    Enum.map(1..count, fn _x ->
      %{name: name} = Alfred.NamesAid.name_add(%{name_add: [type: :imm]})

      assert {:ok, _pid} = Alfred.Name.register(name, opts)

      name
    end)
    |> then(fn names -> %{registered_names: names} end)
  end

  def register_add(_ctx), do: :ok
end
