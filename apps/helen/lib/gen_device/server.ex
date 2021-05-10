defmodule GenDevice do
  defmacro __using__(use_opts) do
    # credo:disable-for-next-line
    quote location: :keep, bind_quoted: [use_opts: use_opts] do
      use GenServer, shutdown: 2000
      use GenDevice.Logic

      import GenDevice.State
      import Helen.Worker.State.Common

      alias GenDevice.Logic

      @use_opts use_opts

      ##
      ## GenServer Start and Initialization
      ##

      @doc false
      @impl true
      def init(args) do
        # just in case we were passed a map?!?
        args = Enum.into(args, [])
        opts = Enum.into(@use_opts, %{})

        Logic.init_server(__MODULE__, args, opts)
      end

      @doc false
      def start_link(opts) do
        GenServer.start_link(__MODULE__, opts, name: __MODULE__)
      end

      @doc """
      Set the device managed by this server to off.

      See `on/1` for options.

      Returns :ok or an error tuple

      ## Examples

          iex> GenDevice.off()
          :ok

      """
      @doc since: "0.0.27"
      def off(opts \\ []) when is_list(opts),
        do: call({:action, %{cmd: :off, worker_cmd: :off, opts: opts}})

      @doc """
      Set the device managed by this server to on.

      Returns :ok, {:ok, reference} or an error tuple
      ## Examples

          iex> on()
          :ok

      ## Option Examples
        `for: [minutes: 1]` switch the device on for the specified duration

        `at_cmd_finish: :off` swith the device off when the cmd is finished

        `notify: [:at_start, :at_finish]` send the caller:
          returns: `{:ok, reference}`

          sends the caller a message when cmd is :at_start or :at_finish:
            {:gen_device,
              %{mod: __MODULE__, cmd: :on | :off, at: :at_start | :at_finish,
                ref: reference, token: nil}}

        `notify: [:at_start, :at_finish, token: term]`
          returns: `{:ok, reference}`

          sends the caller a message when cmd is :at_start or :at_finish:
            {:gen_device,
              %{mod: __MODULE__, cmd: :on | :off, at: :at_start | :at_finish,
                ref: reference, token: token}}
      """
      @doc since: "0.0.27"
      def on(opts \\ []) when is_list(opts),
        do: call({:action, %{cmd: :on, worker_cmd: :on, opts: opts}})

      @doc delegate_to: {__MODULE__, :value, 1}
      defdelegate position, to: __MODULE__, as: :value

      @doc """
      Toggle the devices managed by this server.

      Returns :ok or an error tuple

      ## Examples

          iex> GenServer.toggle([lazy: false])
          :ok

      """
      @doc since: "0.0.27"
      def toggle(opts \\ []) when is_list(opts),
        do: call({:action, %{cmd: :toggle, worker_cmd: :toggle, opts: opts}})

      @doc """
      Return the current status of the device managed by this server.

      Returns a boolean or an error tuple

      ## Examples

          iex> GenServer.value()
          true

      """
      @doc since: "0.0.27"
      def value(opts \\ [:simple]), do: call({:inquiry, {:value, opts}})
    end
  end

  ## END OF QOUTE BLOCK

  ## START OF GenDevice
end
