# Broom

Mutable device command tracker

## Why Broom

Commands may never reach a Remote host due to network interruption, Remote host firmware defects or a
wide variety of other error scenarios. Commands that do reach their intended Remote host are 'acked'
to indicate success. Commands that are never acked are defined as orphans.

Broom provides functionality to detect orphan commands so applications can take appropriate action
(e.g. resend the command) or, at minimum, log the issue to notify the operator.
