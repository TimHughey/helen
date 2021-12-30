defmodule Carol.Instance do
  @moduledoc false

  # def all_child_specs(otp_app) do
  #   config_all = Application.get_all_env(otp_app) || []
  #   {instances, config_rest} = Keyword.pop(config_all, :instances, [])
  #
  #   for {instance, config} <- instances do
  #     child_spec({otp_app, instance, config ++ config_rest})
  #   end
  # end

  @doc since: "0.3.0"
  def child_spec(args) when is_list(args) do
    {restart, start_args} = Keyword.pop(args, :restart, :permanent)

    start_args = Keyword.put_new(start_args, :id, __MODULE__)
    id = start_args[:id]

    %{id: id, start: {Carol.Server, :start_link, [start_args]}, restart: restart}
  end

  def child_spec({app, module, instance}, opts) do
    start_args({app, module, instance}) |> Keyword.merge(opts) |> child_spec()
  end

  def config({otp_app, module}) do
    Application.get_env(otp_app, module, [])
    |> Enum.sort()
  end

  @doc """
  Short name of an instance

  ```
  code
  ```
  """
  @doc since: "0.1.0"
  def display_name(instance) when is_atom(instance) do
    instance
    |> Module.split()
    |> List.last()
    |> then(fn mixed_case -> Regex.scan(~r/[A-Z][a-z]+/, mixed_case) end)
    |> Enum.join(" ")
  end

  @doc """
  Create the id of an instance from module and instance

  ## Example
  ```
  {Carol, :greenhouse} |> Carol.Instance.id()
  #=> Carol.Greenhouse

  ```
  """
  def id({module, instance}) do
    prefix = Module.split(module) |> List.first()
    suffix = to_string(instance) |> Macro.camelize()

    [prefix, suffix] |> Module.concat()
  end

  @doc since: "0.3.0"
  def match_fuzzy(id, string) do
    display_name = display_name(id)

    if Regex.match?(~r/#{string}/i, display_name) do
      {:ok, display_name}
    else
      :no_match
    end
  end

  @doc """
  Create the module name of a `Carol.Instance`

  ## Example
  ```
  # from an atom
  :greenhouse |> Carol.Instance.module()
  #=> Carol.Instance.Greenhouse

  ```
  """
  @doc since: "0.3.0"
  @spec module({module(), atom()}) :: module()
  def module({_module, _instance} = x), do: id(x)

  @doc """
  Creates server start args from `{app, module, instance}`

  ```
  code
  ```
  """
  @doc since: "0.3.0"
  def start_args({app, module, instance}) do
    config_all = config({app, module})

    # grab opts from top-level of config or default to []
    opts = config_all[:opts] || []

    # grabs the instances args from instances list or default to []
    config = get_in(config_all, [:instances, instance]) || []

    [id: id({module, instance}), instance: instance, opts: opts]
    |> Keyword.merge(config)
  end
end
