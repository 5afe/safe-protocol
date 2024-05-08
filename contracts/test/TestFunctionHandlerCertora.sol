// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.18;
import {ISafeProtocolFunctionHandler} from "../interfaces/Modules.sol";

contract TestFunctionHandlerCertora is ISafeProtocolFunctionHandler {
    bool public called;

    function metadataProvider() external view returns (uint256 providerType, bytes memory location) {}

    function supportsInterface(bytes4 interfaceId) external view override returns (bool) {}

    function handle(address, address, uint256, bytes calldata) external override returns (bytes memory) {
        called = true;
        return "";
    }
}
