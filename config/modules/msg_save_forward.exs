use Mix.Config

config :mcp, MessageSave,
  log: [init: false],
  save: true,
  forward: [in: [feed: {"dev/mcr/f/report", 0}]],
  # forward: [],
  purge: [all_at_startup: true, older_than: [minutes: 10], log: true]