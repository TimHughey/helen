defmodule GardenTestHelpers do
  @moduledoc false

  @test_data Path.join(["test", "data"])
  @defaults [cfg_file: Path.join([@test_data, "lighting.toml"])]

  def cfg_toml_file(what)
      when what in [:invalid, :lighting, :parse_fail, :unreadable, :not_found] do
    file = Atom.to_string(what) <> ".toml"

    cfg_file = Path.join([@test_data, file])

    if File.exists?(cfg_file) do
      cfg_file
    else
      cwd = File.cwd!()
      full_path = Path.join([cwd, cfg_file])

      if full_path =~ "not_found.toml" do
        cfg_file
      else
        IO.puts("unable to find: #{full_path}")
        cfg_file
      end
    end
  end

  def make_state(args \\ nil)

  def make_state(nil), do: make_state(@defaults)
  def make_state(:default), do: make_state()

  def make_state(args) when is_list(args) do
    alias Lights.Server

    confirm_state = get_in(args, [:confirm_state])
    confirm_state = if is_nil(confirm_state), do: true, else: confirm_state

    args = Keyword.drop(args, [:confirm_state])

    {:ok, s, _} = Server.init(args)
    {rc, s, _} = Server.handle_continue(:load_cfg, s)

    cond do
      confirm_state and :noreply == rc -> {:ok, s}
      confirm_state and not is_map_key(s, [:error]) -> {:failed, s}
      true -> {:ok, s}
    end
  end

  defmacro pretty(x) do
    quote do
      "\n#{inspect(unquote(x), pretty: true)}"
    end
  end

  def reset_data_file_permissions do
    files = Path.wildcard([@test_data, "*.toml"])

    for file <- files do
      File.chmod(file, 0o644)
    end
  end
end
