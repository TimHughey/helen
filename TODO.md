# Fat Helen and Ruth To Do List

## In Flight Changes

[ ] Switch and PulseWidth must load the Command Alias association

## Alfred

[ ] validate just seen alias names match existing known name
[ ] periodic prune of dead devies and notification registrations

## Broom

[X] rename BroomTester.Commands to BroomTester.Execute to create reference implementation
[ ] write typespecs for all structs and callbacks
[X] implement Broom behaviour
[ ] implement cmd purging
[ ] implement startup orphan check
[ ] add error logging for invalid iso8601 durations

## Garden Lighting

[ ] harden on/off to recover from Ruth restarts

## Incoming Message

[ ] make separate app
[ ] use structs
[ ] ensure all msg processing faults are binaries

## Ruth

[ ] adjust Switch and PWM reporting to match Helen changes
[ ] Sensors must report datapoints instead of readings

## Ruth Sim

[ ] remove duplicate code across Sensor, Switch and PulseWidth

## Sensor, Switch and PulseWidth

[ ] implement dead device deletion with check for aliases still using dead device
