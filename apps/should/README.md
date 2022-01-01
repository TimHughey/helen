# Should

Helpers for unit test debugging

## History

`Should` was a collection of unit test helpers for asserting deeply nested key/values
and data types originally created.

`ExUnit` assertion pattern matching has advanced significantly. As a principle it is always better to
use native language functionality. Going forward `ExUnit` will be used due to the robust pattern
matching capability available.

`Should` has been replaced by the native `ExUnit` functionality as of 2022-01-01.

It is worth noting, however, there is functionality in `Should` that may be brought
back to simplify unit testing in the future. For now, though, `ExUnit` native functionality is
the intention.
