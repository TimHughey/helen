defmodule GardenConfigTest do
  @moduledoc false

  use ExUnit.Case, async: true
  use Should
  use Timex

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

      cfg =
        Garden.Config.Decode.file_to_map(ctx.cfg_file)
        |> Garden.Config.new()

      {duration, res} = Duration.measure(Garden.Config, :equipment_cmds, [cfg, now])

      assert should_be_non_empty_map(res)

      execute_ms = Duration.to_milliseconds(duration)

      assert execute_ms < 2.0, "execute duration should be less than 2 milliseconds: #{execute_ms}"
    end

    @tag cfg_file: "test/toml/config.toml"
    test "success: can calculate schedule timeline", ctx do
      now = Timex.local()

      cfg =
        Garden.Config.Decode.file_to_map(ctx.cfg_file)
        |> Garden.Config.new()

      {duration, res} = Duration.measure(Garden.Config, :make_timeline, [cfg, now])

      should_be_non_empty_list(res)

      execute_ms = Duration.to_milliseconds(duration)

      assert execute_ms < 2.0, "execute duration should be less than 2 milliseconds: #{execute_ms}"

      # inspect(res, pretty: true) |> IO.puts()
    end

    @tag cfg_file: "test/toml/config.toml"
    test "success: can calculate next wakeup ms", ctx do
      now = Timex.local()

      cfg = Garden.Config.Decode.file_to_map(ctx.cfg_file) |> Garden.Config.new()

      res = Garden.Config.next_wakeup_ms(cfg, now)
      assert is_integer(res) and res > 0, "should return integer > 0: #{inspect(res)}"

      inspect(res, pretty: true) |> IO.puts()
    end

    @tag cfg_file: "test/toml/config.toml"
    test "success: can calculate next wakeup ms at end of day threshold", ctx do
      now = Timex.local() |> Timex.end_of_day()

      cfg = Garden.Config.Decode.file_to_map(ctx.cfg_file) |> Garden.Config.new()

      res = Garden.Config.next_wakeup_ms(cfg, now)

      assert is_integer(res) and res == 1000, "should return integer == 1000: #{inspect(res)}"
    end
  end
end
