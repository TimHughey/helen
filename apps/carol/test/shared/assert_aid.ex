defmodule Carol.AssertAid do
  defmacro __using__(use_opts) do
    quote location: :keep, bind_quoted: [use_opts: use_opts] do
      @carol_test_module use_opts[:module] || []

      if is_atom(@carol_test_module) do
        @carol_test_id Module.split(@carol_test_module) |> List.first()

        describe "#{inspect(@carol_test_module)}.children/0" do
          test "returns list of children" do
            children = @carol_test_module.which_children()

            assert Enum.all?(children, fn child ->
                     assert {id, pid, _, _} = child
                     assert [@carol_test_id | _] = Module.split(id)
                     assert Process.alive?(pid)
                   end)
          end
        end
      else
        """

        To auto generate the Carol tests you must specify a module (usually the
        top most module). Until you do so the Carol tests will not execute.

        For example:

        use Carol.AssertAid, [module: SomeModule]

        """
        |> IO.puts()
      end
    end
  end
end
