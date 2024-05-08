**:warning: This repository is not actively developed at the moment. :warning:**

[![Coverage Status](https://coveralls.io/repos/github/safe-global/safe-core-protocol/badge.svg)](https://coveralls.io/github/safe-global/safe-core-protocol)

# Safe{Core} Protocol

This project is an implementation of [Safe{Core} Protocol specification](https://github.com/safe-global/safe-core-protocol-specs)

## Architecture

Safe{Core} Protocol implementation consists of following main components:

-   [SafeProtocolManager](./contracts/SafeProtocolManager.sol)
-   [SafeProtocolRegistry](./contracts/SafeProtocolRegistry.sol)
-   [Interfaces for Modules](./contracts/interfaces/Modules.sol)

A high level overview of the architecture is as follows:

```mermaid
graph TD
    Account -->|Execute transaction| Monitor
    Account -->|Manage Modules| Store
    Account -->|SafeProtocolManager handling fallback functionality| FunctionHandlerSupport
    PluginInstance(Plugin Instance) -->|Execute transaction from Plugin| Monitor
    RegistryOwner("Registry Owner") --> Maintain
    RegistryOwner("Registry Owner") --> Flag

subgraph SafeProtocolManager
	Store(Maintain Enabled Modules per Safe)
    Monitor(Mediate Account transaction execution)
    FunctionHandlerSupport("Provide additional functionality using Function Handler(s)")
    HooksSupport("Hooks for validating transaction execution")
    Monitor -.- HooksSupport
end

subgraph SafeProtocolRegistry
	AllowQuery(Provide information about Modules)
    Maintain("Maintain list of permitted Modules")
    Flag("Mark Module as Malicious")
    Monitor -...- AllowQuery
    Store -...- AllowQuery
end
```

### Modules

```mermaid
graph TD
style Modules font-size:20px;
subgraph Modules
	Plugin(Plugin)
	Hooks(Hooks)
	FunctionHandler(Function Handler)
	SignatureValidator(Signature validator)
end
```

Currently implemented components of the Safe{Core} Protocol are:

-   **SafeProtocolManager**
-   **SafeProtocolRegistry**
-   **Plugins**
-   **Hooks**
-   **Function Handler**
-   Additionally a test version of registry **TestSafeProtocolRegistryUnrestricted** is also available.

[Execution flows](./docs/execution_flows.md) give a high-level overview of the different flows for the Safe{Core} Protocol.

## Deployments

All the deployed addresses of contracts are available in [deployments.ts](./deployments.ts) for each network along with contract abis. Alternatively, all the addresses are also available in a [markdown file](./docs/deployments.md)

## Using solidity interfaces

The solidity interfaces for the Safe{Core} Protocol contracts are available in [interfaces](./contracts/interfaces) directory. These interfaces are available for import into solidity smart contracts via the npm artifact.

To install the npm package, run the following command:

```bash
npm i @safe-global/safe-core-protocol
```

E.g. Create a plugin

```solidity
import {ISafeProtocolPlugin} from "@safe-global/safe-core-protocol/contracts/interfaces/Modules.sol";

contract SamplePlugin is ISafeProtocolPlugin {

    function name() external view returns (string memory name) {
        ...
    }

    function version() external view returns (string memory version){
        ...
    }

    function metadataProvider() external view returns (uint256 providerType, bytes memory location){
        ...
    }

    function requiresPermissions() external view returns (uint8 permissions){
        ...
    }

}
```

For more examples and information on adding Module(s) to the Registry, refer to [Safe{Core} Protocol demo](https://github.com/safe-global/safe-core-protocol-demo/tree/main/contracts)

## Useful commands

### Install

```bash
yarn
```

### Compile

```bash
yarn hardhat compile
```

### Test

```bash
yarn hardhat test
```

### Deploy

-   Deploy test contracts network to goerli.
    -   [test registry](./contracts/test/TestSafeProtocolRegistryUnrestricted.sol)
    -   [test manager](./contracts/test/TestSafeProtocolManager.sol)
    ```bash
    yarn hardhat deploy --network goerli --tags test-protocol --export-all deployments.ts
    ```
-   Deploy contracts with [SafeProtocolRegistry](./contracts/test/TestSafeProtocolRegistryUnrestricted.sol) registry network to goerli.
    ```bash
    yarn hardhat deploy --network goerli --tags protocol --export-all deployments.ts
    ```

### Other commands

| Command                                                                                      | Description                                                                                                                          |
| -------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------ |
| `yarn hardhat generate:deployments`                                                          | Generate deployments markdown in [./docs/deployments.md](./docs/deployments.md) from [./deployments.ts](./deployments.ts)            |
| `yarn hardhat verify --network goerli <contract_address> <initial_owner>`                    | Verify Registry contract(s)<br/> Applicable for<br/> - SafeProtocolRegistry.sol<br/> - TestSafeProtocolRegistryUnrestricted.sol<br/> |
| `yarn hardhat verify --network goerli <contract_address> <initial_owner> <registry_address>` | Verify SafeProtocolManager.sol                                                                                                       |
