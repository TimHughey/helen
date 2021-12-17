import Config

config :sally, Sally.Host, profiles_path: "host_profiles"

config :sally, Sally.Host.Firmware,
  opts: [
    search_paths: ["/dar/www/wisslanding/htdocs/sally"],
    dir: "firmware",
    file_regex: [~r/\d\d\.\d\d\.\d\d.+-ruth\.bin$/]
  ]
