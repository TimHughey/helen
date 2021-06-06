Application.ensure_all_started(:sally)

Sally.Test.Support.delete_dev_aliases()

ExUnit.start()
