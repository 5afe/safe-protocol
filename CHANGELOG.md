# Changelog

This changelog contains changes starting from version v0.1.0

# Version 0.3.0 Alpha

## Safe{Core} Protocol contracts

### Changes

- A module can only be registered once with a single type [#103](https://github.com/safe-global/safe-core-protocol/issues/103)

  Update registry interface so that a contract can be added as multiple types

- Include constants and datatypes in npm package [#119](https://github.com/safe-global/safe-core-protocol/pull/119/files)

# Version 0.2.1 Alpha

## Safe{Core} Protocol contracts

### Changes

- Implement fine grained permissions [#98](https://github.com/safe-global/safe-core-protocol/pull/98)

  Implement more granular permissions for plugins

- Remove ISafe interface in the function handler [#99](https://github.com/safe-global/safe-core-protocol/pull/99)

  Replace ISafe interface in the function handler parameters with an account address

# Version 0.2.0

## Safe{Core} Protocol contracts

### Changes

- Issue [#47](https://github.com/safe-global/safe-core-protocol/issues/47)

    Allow setting Function Handler for individual function selector per Safe

- Issues [#73](https://github.com/safe-global/safe-core-protocol/issues/73)

    Check if the contract supports the appropriate interface while enabling a Plugin

- Issue [#46](https://github.com/safe-global/safe-core-protocol/issues/46)

    Add support for hooks in multi-signature execution flow for a Safe

- Issue [#62](https://github.com/safe-global/safe-core-protocol/issues/62)

    Allow the `to` value to be the account address in executeTransaction when the caller has root access

- Issue [#71](https://github.com/safe-global/safe-core-protocol/issues/71)

    Fixed broken linked list after disabling the plugin in the Manager

# Version 0.1.0

## Safe{Core} Protocol contracts

### Changes

- Issue [#1](https://github.com/safe-global/safe-core-protocol/issues/1)

    Setup project

- Issue [#2](https://github.com/safe-global/safe-core-protocol/issues/2)

    Create interfaces

- Issue [#3](https://github.com/safe-global/safe-core-protocol/issues/3)

    Create simple registry

- Issue [#4](https://github.com/safe-global/safe-core-protocol/issues/4)

    Create Manager contract and allow enabling Plugin on an account
