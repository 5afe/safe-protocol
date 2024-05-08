// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.18;
import {ISafeProtocolHooks} from "../../interfaces/Modules.sol";
import {IAccount} from "../../interfaces/Accounts.sol";
import {SafeProtocolAction, SafeTransaction, SafeRootAccess} from "../../DataTypes.sol";

contract TestHooksCertora is ISafeProtocolHooks {
    bool public called;

    function supportsInterface(bytes4 interfaceId) external view override returns (bool) {}

    function preCheck(address, SafeTransaction calldata, uint256, bytes calldata) external override returns (bytes memory) {
        called = true;
        return "";
    }

    function preCheckRootAccess(address, SafeRootAccess calldata, uint256, bytes calldata) external override returns (bytes memory) {
        called = true;
        return "";
    }

    function postCheck(address, bool, bytes calldata) external override {
        called = true;
    }
}
