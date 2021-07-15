defmodule Eva.Opts.Server do
  alias __MODULE__

  defstruct id: nil, name: nil, genserver: []

  @type t :: %Server{
          id: atom(),
          name: module(),
          genserver: list()
        }
end

defmodule Eva.Opts do
  alias __MODULE__
  alias Eva.Opts.Server

  defstruct server: %Server{},
            toml_file: nil,
            description: "<none>",
            initial_mode: :ready,
            valid?: true,
            invalid_reason: nil

  @type t :: %Opts{
          server: Server.t(),
          toml_file: Path.t(),
          initial_mode: :ready | :standby | :error,
          valid?: boolean(),
          invalid_reason: nil | any()
        }

  def append_cfg(toml_rc, %Opts{} = opts) do
    case toml_rc do
      {:ok, cfg} ->
        desc = cfg[:description] || opts.description
        mode = String.to_atom(cfg[:initial_mode]) || opts.initial_mode
        %Opts{opts | description: desc, initial_mode: mode}

      {:error, error} ->
        %Opts{opts | initial_mode: :error, valid?: false, invalid_reason: error}
    end
  end

  def make_opts(mod, start_opts, use_opts) do
    cfg_path = System.get_env(start_opts[:env_vars][:cfg_path], ".")
    cfg_file = System.get_env(start_opts[:env_vars][:cfg_file], "not_specified.toml")
    toml_file = [cfg_path, cfg_file] |> Path.join()

    {id, rest} = Keyword.pop(use_opts, :id, mod)
    {name, genserver_opts} = Keyword.pop(rest, :name, mod)

    %Opts{server: %Server{id: id, name: name, genserver: genserver_opts}, toml_file: toml_file}
  end

  def server_name(%Opts{} = opts), do: opts.server.name

  def valid?(%Opts{} = opts), do: opts.valid?
end
