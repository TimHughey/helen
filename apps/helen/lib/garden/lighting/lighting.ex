defmodule Lighting do
  @moduledoc """
    Lighting Implementation for Wiss Landing
  """

  alias Garden.Lighting.{Opts, Server}

  @doc delegate_to: {Opts, :default_opts, 0}
  defdelegate opts, to: Opts, as: :default_opts

  @doc """
  Return a keyword list of the scheduled irrigation jobs scheduled.

  ## Examples

      iex> Lighting.scheduled_jobs()
      [irrigation_flower_boxes_am: ~e[27 5 23 6 * *]]

  """
  @doc since: "0.0.27"
  def scheduled_jobs do
    all_jobs = Helen.Scheduler.jobs()

    for {name, details} <- all_jobs do
      name_parts = Atom.to_string(name) |> String.split("_")

      if String.contains?(hd(name_parts), "garden") do
        %_{schedule: schedule} = details

        {name, schedule}
      else
        []
      end
    end
    |> List.flatten()
  end

  @doc delegate_to: {Server, :start_job, 3}
  defdelegate start_job(job_name, job_tod, token), to: Server

  @doc """
  Manually start Garden Lighting jobs.

  Time of day options: day, evening, night (default)

  ## Examples

      iex> Lighting.start_jobs_manual(time_of_day)

  """
  @doc since: "0.0.28"
  def start_jobs_manual(tod \\ :night) when tod in [:day, :evening, :night] do
    token = Server.token()

    for job <- [:porch, :red_maple, :evergreen] do
      {job, start_job(job, tod, token)}
    end
  end

  @doc delegate_to: {Server, :timeouts, 0}
  defdelegate timeouts, to: Server

  @doc delegate_to: {Server, :restart, 0}
  defdelegate restart, to: Server

  @doc delegate_to: {Server, :state, 0}
  defdelegate x_state, to: Server
end
