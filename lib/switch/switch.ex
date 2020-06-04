defmodule Switch do
  @moduledoc ~S"""
  Switch

  Primary entry module for all Switch functionality.
  """

  require Logger

  alias Switch.{Alias, Device}

  defmacro __using__([]) do
    quote do
      def sw_position(name, opts \\ [])

      def sw_position(name, opts) when is_list(opts) do
        ensure = Keyword.get(opts, :ensure, false)
        position = Keyword.get(opts, :position, nil)

        if ensure and is_boolean(position) do
          unquote(__MODULE__).position_ensure(name, opts)
        else
          Switch.Alias.position(name, opts)
        end
      end
    end
  end

  #
  ## Public API
  #

  def aliases(mode \\ :print) do
    import Ecto.Query, only: [from: 2]

    cols = [{"Name", :name}, {"Status", :status}, {"Position", :position}]

    aliases =
      for %Switch.Alias{name: name} <-
            from(x in Switch.Alias, order_by: x.name) |> Repo.all() do
        {rc, position} = Switch.position(name)
        %{name: name, status: rc, position: position}
      end

    case mode do
      :print ->
        Scribe.print(aliases, data: cols)

      :browse ->
        Scribe.console(aliases, data: cols)

      :raw ->
        aliases

      true ->
        Enum.count(aliases)
    end
  end

  @doc """
    Public API for creating a Sensor Alias
  """
  @doc since: "0.0.21"
  def alias_create(device_or_id, name, pio, opts \\ []) do
    alias Switch.{Alias, Device}

    # first, find the device to alias
    with %Device{device: dev_name} = dev <- device_find(device_or_id),
         # create the alias and capture it's name
         {:ok, %Alias{name: name}} <- Alias.create(dev, name, pio, opts) do
      [created: [name: name, device: dev_name, pio: pio]]
    else
      nil -> {:not_found, device_or_id}
      error -> error
    end
  end

  @doc """
  Finds a Switch Alias by name or id

  opts are passed as-is to Repo.preload/2
  """

  @doc since: "0.0.21"
  defdelegate alias_find(name_or_id, opts), to: Alias, as: :find

  @doc """
    Find a Switch Device by device or id
  """
  @doc since: "0.0.21"
  defdelegate device_find(device_or_id), to: Device, as: :find

  @doc """
    Find a the alias of a Device using pio
  """
  @doc since: "0.0.21"
  def device_find_alias(device_or_id, name, pio, opts \\ []) do
    alias Switch.Device

    with %Device{} = dev <- device_find(device_or_id) do
      Device.find_alias(dev, name, pio, opts)
    else
      _not_found -> {:not_found, device_or_id}
    end
  end

  @doc """
    Retrieve a list of devices that begin with a pattern
  """
  @doc since: "0.0.21"
  def devices_begin_with(pattern) when is_binary(pattern) do
    import Ecto.Query, only: [from: 2]

    like_string = [pattern, "%"] |> IO.iodata_to_binary()

    from(x in Device,
      where: like(x.device, ^like_string),
      order_by: x.device,
      select: x.device
    )
    |> Repo.all()
  end

  def position(name, opts \\ []) when is_binary(name) and is_list(opts) do
    Switch.Alias.position(name, opts)
  end

  #
  ## Private
  #

  def position_ensure(name, opts) do
    pos_wanted = Keyword.get(opts, :position)
    {rc, pos_current} = sw_rc = Alias.position(name)

    with {:switch, :ok} <- {:switch, rc},
         {:ensure, true} <- {:ensure, pos_wanted == pos_current} do
      # position is correct, return it
      sw_rc
    else
      # there was a problem with the switch, return
      {:switch, _error} ->
        sw_rc

      # switch does not match desired position, force it
      {:ensure, false} ->
        # force the position change
        opts = Keyword.put(opts, :lazy, false)
        Alias.position(name, opts)

      error ->
        log_position_ensure(sw_rc, error, name, opts)
    end
  end

  #
  ## Logging
  #

  defp log_position_ensure(sw_rc, error, name, opts) do
    Logger.warn([
      "unhandled position_ensure() condition\n",
      "name: ",
      inspect(name, pretty: true),
      "\n",
      "opts: ",
      inspect(opts, pretty: true),
      "\n",
      "error: ",
      inspect(error, pretty: true)
    ])

    sw_rc
  end
end
