defmodule Carol.Supervisor do
  @moduledoc false
  use Supervisor

  @doc """
  Starts the Carol app supervisor.
  """
  def start_link({otp_app, sup_mod}, opts) do
    name = Keyword.get(opts, :name, sup_mod)
    sup_opts = [name: name, strategy: :one_for_one]

    instances = opts[:instances] || []

    num_instances = Enum.count(instances)

    sup_opts = sup_opts ++ [max_restarts: num_instances * 3, num_seconds: 3]

    {otp_app, sup_mod}
    |> all_child_specs(instances)
    |> Supervisor.start_link(sup_opts)
  end

  @doc """
  Retrieves the runtime configuration.
  """
  def runtime_config(otp_app, mod, _opts) do
    config = Application.get_env(otp_app, mod, [])
    config = [otp_app: otp_app] ++ config

    case config do
      [] -> :ignore
      config when is_list(config) -> {:ok, config}
    end
  end

  @doc """
  Retrieves the compile time configuration.
  """
  def compile_config(opts) do
    otp_app = Keyword.fetch!(opts, :otp_app)

    {otp_app}
  end

  ## Callbacks

  @doc false
  @impl true
  def init(args) do
    #  args |> tap(fn x -> inspect(x, pretty: true) |> IO.puts() end)

    Supervisor.init(args, strategy: :one_for_one, max_restarts: 10)
  end

  ## PRIVATE
  ## PRIVATE
  ## PRIVATE

  defp all_child_specs({otp_app, sup_mod}, instances) do
    for {instance, args} <- instances do
      Carol.Instance.child_spec({otp_app, sup_mod, instance}, args)
    end
  end
end
