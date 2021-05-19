import Config

config :betty, Betty.Connection,
  http_opts: [insecure: true],
  pool: [max_overflow: 10, size: 10, timeout: 5_000, max_connections: 10],
  port: 8086,
  scheme: "http",
  writer: Instream.Writer.Line

import_config "#{config_env()}.exs"
