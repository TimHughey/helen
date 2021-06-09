# Fat Helen and Ruth To Do List

## Alfred

- [ ] periodic prune of dead devies and notification registrations
- [ ] remove support for old Helen devices and aliases

## Broom

- [ ] adjust reference implementation to match Sally
- [x] rename BroomTester.Commands to BroomTester.Execute to create reference implementation
- [ ] write typespecs for all structs and callbacks
- [x] implement Broom behaviour
- [ ] implement auto ack of pending cmds at shutdown
- [ ] implement cmd purging
- [ ] implement startup orphan check
- [ ] add error logging for invalid iso8601 durations

## Garden Lighting

- [ ] harden on/off to recover from Ruth restarts

## Ruth

- [ ] adjust Switch and PWM reporting to match Helen changes
- [ ] Sensors must report datapoints instead of readings

## Ruth Sim

- [ ] remove duplicate code across Sensor, Switch and PulseWidth

## Sally

- Mutable (e.g. PulseWidth, Switch) devices and aliases
- Immutable (e.g. Sensor) devices and aliases
- RemoteHosts (e.g. Ruth)
- MQTT connection and handler

### Sally Host

- [ ] add metrics reporting for boot message

### Mutables

#### Common

- [ ] implement dead device deletion with pre-check for aliases

##### MsgIn

- [ ] ensure all msg processing faults are binaries

### Should

- [ ] remove support for old device status checks
