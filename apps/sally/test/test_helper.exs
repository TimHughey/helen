Application.ensure_all_started(:sally)

Sally.PulseWidth.TestSupport.delete_dev_aliases("")

ExUnit.start()
