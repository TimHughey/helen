defmodule Carol do
  @moduledoc """
  Carol controls equipment using a daily schedule
  """

  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts] do
      @behaviour Carol

      {otp_app} = Carol.Supervisor.compile_config(opts)

      @otp_app otp_app

      def config do
        {:ok, config} = Carol.Supervisor.runtime_config(@otp_app, __MODULE__, [])
        config |> Enum.sort()
      end

      # NOTE: Supervisor child_spec
      @doc false
      def child_spec(opts) do
        config = config()

        %{
          id: __MODULE__,
          start: {__MODULE__, :start_link, [config]},
          type: :supervisor
        }
      end

      def instances do
        Keyword.get(config(), :instances, []) |> Keyword.keys() |> Enum.sort()
      end

      def start_link(opts \\ []) do
        Carol.Supervisor.start_link({@otp_app, __MODULE__}, opts)
      end

      def which_children, do: Supervisor.which_children(__MODULE__)
    end
  end

  @type instance() :: atom() | String.t()
  @type ok_failed() :: :ok | :failed
  @type opts() :: list()
  @type start_args() :: list()

  @callback config :: list()
  @callback instances :: list()
  @callback start_link(start_args()) :: {:ok, pid()}

  # NOTE:
  # all status and command functions are exposed via
  # Alfred.status/2 and Alfred.execute/2
end
