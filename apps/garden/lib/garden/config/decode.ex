defmodule Garden.Config.Decode do
  def file_to_map(file) do
    Toml.decode_file(file, keys: :atoms, transforms: Garden.Config.Transforms.all())
  end
end
