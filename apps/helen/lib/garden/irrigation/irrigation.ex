defmodule Irrigation do
  @moduledoc """
    Irrigation Implementation for Wiss Landing
  """

  alias Garden.Irrigation.{Opts, Server}

  @doc delegate_to: {Opts, :default_opts, 0}
  defdelegate opts, to: Opts, as: :default_opts

  @doc delegate_to: {Server, :start_job, 1}
  defdelegate start_job(job_name, job_atom, tod_atom, duration_list),
    to: Server

  @doc delegate_to: {Server, :timeouts, 0}
  defdelegate timeouts, to: Server

  @doc """
  Execute a oneshot irrigation of the flower boxes

  Default "PT45S"

  Returns :ok

  ## Examples

      iex> Irrigation.fflower_boxes_oneshot()
      :ok

      iex> Irrigation.flower_boxes_oneshot("PT45S")
      :ok

  """
  @doc since: "0.0.27"
  def flower_boxes_oneshot(opts \\ "PT45S") do
    Server.start_job(:flower_boxes_oneshot, :flower_boxes, :oneshot, opts)
  end

  @doc """
  Execute a oneshot irrigation of the garden

  Default "PT45S"

  Returns :ok

  ## Examples

      iex> Irrigation.garden_oneshot()
      :ok

      iex> Irrigation.garden_oneshot([minutes: 30])
      :ok

  """
  @doc since: "0.0.27"
  def garden_oneshot(opts \\ "PT30M") do
    Server.start_job(:garden_oneshot, :garden, :oneshot, opts)
  end

  @doc """
  Return a keyword list of the scheduled irrigation jobs scheduled.

  ## Examples

      iex> Irrigation.scheduled_jobs()
      [irrigation_flower_boxes_am: ~e[27 5 23 6 * *]]

  """
  @doc since: "0.0.27"
  def scheduled_jobs do
    all_jobs = Helen.Scheduler.jobs()

    for {name, details} <- all_jobs do
      name_parts = Atom.to_string(name) |> String.split("_")

      if String.contains?(hd(name_parts), "irrigation") do
        %_{schedule: schedule} = details

        {name, schedule}
      else
        []
      end
    end
    |> List.flatten()
  end

  @doc delegate_to: {Server, :restart, 0}
  defdelegate restart, to: Server

  @doc delegate_to: {Server, :state, 0}
  defdelegate x_state, to: Server
end
