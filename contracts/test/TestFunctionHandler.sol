// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.18;
import {ISafeProtocolFunctionHandler} from "../interfaces/Integrations.sol";
import {ISafe} from "../interfaces/Accounts.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

contract TestFunctionHandler is ISafeProtocolFunctionHandler {
    uint256 public inc;

    function supportsInterface(bytes4 interfaceId) external view override returns (bool) {
        return type(IERC165).interfaceId == interfaceId || type(ISafeProtocolFunctionHandler).interfaceId == interfaceId;
    }

    function handle(ISafe, address, uint256, bytes calldata) external override returns (bytes memory result) {
        inc++;
        result = abi.encode(inc);
    }

    function metadataProvider() external view override returns (uint256 providerType, bytes memory location) {}
}
