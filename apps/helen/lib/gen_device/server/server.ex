defmodule GenDevice do
  @moduledoc """
  Controls mulitple devices based on a series of commands
  """

  defmacro __using__(use_opts) do
    # credo:disable-for-next-line
    quote location: :keep, bind_quoted: [use_opts: use_opts] do
      use GenServer, restart: :transient, shutdown: 7000
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
        do: call({:execute, %{cmd: :toggle, opts: opts}})

      @doc """
      Return the current value (position) off the device managed by this server.

      Returns a boolean or an error tuple

      ## Examples

          iex> GenServer.value()
          true

      """
      @doc since: "0.0.27"
      def value(opts \\ []), do: call({:inquiry, {:value, opts}})

      # @doc false
      # @impl true
      # # handle the case when the msg_token matches the current state.
      # def handle_info(
      #       {:timer, %{inflight: %{token: msg_token} = action}},
      #       %{token: token} = state
      #     )
      #     when msg_token == token do
      #   state
      #   |> inflight_status(:finished)
      #   |> send_at_timer_msg_if_needed(action)
      #   |> adjust_device_if_needed(action)
      #   |> put_in([:active_cmd], :none)
      #   |> noreply()
      # end
      #
      # # NOTE:  when the msg_token does not match the state token then
      # #        a change has occurred so ignore this timer message
      # def handle_info({:timer, _msg, _msg_token}, s) do
      #   noreply(s)
      # end

      ##
      ## PRIVATE
      ##

      #
      # # this function matches the call from :at_end
      # defp send_at_timer_msg_if_needed(
      #        state,
      #        # orignal cmd message
      #        {cmd, cmd_opts, reply_pid},
      #        category
      #      ) do
      #   # if the matching ':at' option was specified
      #   for {:notify, notify_opts} <- cmd_opts,
      #       at_opt when at_opt == category <- notify_opts do
      #     # extract the token from the opts, if included.
      #     # since the notifiy opts are a mix of atoms and keywords
      #     # let's use a for loop, with an accumulator starting with nil
      #     # if this for loop finds [token: term] then term is the result
      #     token =
      #       for {:token, v} <- notify_opts, reduce: nil do
      #         token -> v
      #       end
      #
      #     # assemble the payload map that is always sent regardless if
      #     # the token opt is passed
      #     payload = %{
      #       mod: __MODULE__,
      #       cmd: cmd,
      #       at: category,
      #       ref: state[:lasts][:reference],
      #       token: token
      #     }
      #
      #     msg = {:gen_device, payload}
      #
      #     send(reply_pid, msg)
      #   end
      #
      #   state
      # end
      #
    end
  end

  ## END OF QOUTE BLOCK

  ## START OF GenDevice
end
