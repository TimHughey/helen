defmodule SallyDevAliasTest do
  use ExUnit.Case, async: true
  use Should

  @host_ident_default "sally.hostdevalias0"
  @host_name_default "Sally Host Dev Alias Test"

  @moduletag db_test: true, sally_dev_alias: true

  alias Sally.Test.Support

  setup_all ctx do
    ctx
  end

  setup [:setup_init]

  test "can DevAlias create an alias" do
    host_opts = [ident: @host_ident_default, name: @host_name_default]
    device_opts = [ident: "dev_alias_test01", family: "ds", mutable: false]

    device = Support.add_host(host_opts) |> Support.add_device(device_opts)

    dev_alias_opts = [name: "First Sensor Alias", pio: 0]
    dev_alias = Sally.DevAlias.create(device, dev_alias_opts)

    should_be_schema(dev_alias, Sally.DevAlias)

    fail = pretty("created DevAlias did not match", dev_alias)
    assert dev_alias.name == dev_alias_opts[:name], fail
    assert dev_alias.pio == dev_alias_opts[:pio], fail
  end

  defp setup_init(ctx) do
    # put = fn res, x -> put_in(ctx, [x], res) end
    #
    # run_setup = if ctx[:setup] |> is_nil(), do: true, else: ctx[:setup]
    # if run_setup, do: ctx |> default_msg_in() |> Handler.handle_message() |> put.(:handler), else: ctx

    ctx
  end
end
