defmodule GardenConfigTest do
  @moduledoc false

  use ExUnit.Case, async: true
  use Should

  setup_all ctx do
    ctx
  end

  describe "Garden Config Parse" do
    @tag cfg_file: "test/toml/config.toml"
    test "success: can parse config file", ctx do
      cfg = Garden.Config.Decode.file_to_map(ctx.cfg_file) |> Garden.Config.new()

      should_be_struct(cfg, Garden.Config)

      fail = "irrigation power should be binary: #{inspect(cfg.irrigation_power)}"
      assert is_binary(cfg.irrigation_power), fail

      # cfg |> inspect(pretty: true) |> IO.puts()
    end

    @tag cfg_file: "test/toml/config.toml"
    test "success: can get unique equipment names", ctx do
      res =
        Garden.Config.Decode.file_to_map(ctx.cfg_file)
        |> Garden.Config.new()
        |> Garden.Config.equipment()

      should_be_non_empty_list(res)
      assert length(res) == 6, "there should be six pieces of equipment"

      # res |> inspect(pretty: true) |> IO.puts()
    end

    @tag cfg_file: "test/toml/config.toml"
    test "success: can calculate equipment commands", ctx do
      now = Solar.event("astro rise")

      res =
        Garden.Config.Decode.file_to_map(ctx.cfg_file)
        |> Garden.Config.new()
        |> Garden.Config.equipment_cmds(now)

      assert should_be_non_empty_map(res)

      inspect(res, pretty: true)
      |> IO.puts()

      assert true
    end
  end
end
