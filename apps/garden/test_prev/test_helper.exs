if File.exists?(GardenTestHelpers.cfg_toml_file(:lighting)) do
  files = Path.wildcard("./test/data/*.toml")

  for file <- files do
    File.chmod(file, 0o644)
  end

  ExUnit.start()

  files = Path.wildcard("./test/data/*.toml")

  for file <- files do
    File.chmod(file, 0o644)
  end
else
  case File.cwd() do
    {:ok, cwd} -> IO.puts("unable to find test data: #{cwd}")
    error -> IO.puts("error finding test data: #{inspect(error)}")
  end
end
