// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.18;
import {IAccount} from "../interfaces/Accounts.sol";

contract TestExecutorCertora is IAccount {
    bool public called;
    address public module;
    address[] public owners;
    address public fallbackHandler;
    bytes public data;

    constructor(address _fallbackHandler) {
        fallbackHandler = _fallbackHandler;
    }

    function setModule(address _module) external {
        module = _module;
    }

    function setFallbackHandler(address _fallbackHandler) external {
        fallbackHandler = _fallbackHandler;
    }

    function exec(address payable to, uint256 value, bytes calldata data) external {
        bool success;
        bytes memory response;
        (success, response) = to.call{value: value}(data);
        if (!success) {
            // solhint-disable-next-line no-inline-assembly
            assembly {
                revert(add(response, 0x20), mload(response))
            }
        }
    }

    function execTransactionFromModule(address payable, uint256, bytes calldata, uint8) external returns (bool success) {
        called = true;
        success = true;
    }

    function execTransactionFromModuleReturnData(
        address,
        uint256,
        bytes memory,
        uint8
    ) public returns (bool success, bytes memory returnData) {
        called = true;
        success = true;
        returnData = data;
    }

    function executeCallViaMock(
        address payable to,
        uint256 value,
        bytes memory,
        uint256 gas
    ) external returns (bool success, bytes memory response) {
        (success, response) = to.call{value: value, gas: gas}(data);
        if (!success) {
            // solhint-disable-next-line no-inline-assembly
            assembly {
                revert(add(response, 32), mload(response))
            }
        }
    }

    // @notice Forwards all calls to the fallback handler if set. Returns 0 if no handler is set.
    // @dev Appends the non-padded caller address to the calldata to be optionally used in the handler
    //      The handler can make us of `HandlerContext.sol` to extract the address.
    //      This is done because in the next call frame the `msg.sender` will be FallbackManager's address
    //      and having the original caller address may enable additional verification scenarios.
    // Source: https://github.com/safe-global/safe-contracts/blob/main/contracts/base/FallbackManager.sol#L62
    // solhint-disable-next-line payable-fallback,no-complex-fallback
    fallback() external {
        address handler = fallbackHandler;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            // When compiled with the optimizer, the compiler relies on a certain assumptions on how the
            // memory is used, therefore we need to guarantee memory safety (keeping the free memory point 0x40 slot intact,
            // not going beyond the scratch space, etc)
            // Solidity docs: https://docs.soliditylang.org/en/latest/assembly.html#memory-safety
            function allocate(length) -> pos {
                pos := mload(0x40)
                mstore(0x40, add(pos, length))
            }

            if iszero(handler) {
                return(0, 0)
            }

            let calldataPtr := allocate(calldatasize())
            calldatacopy(calldataPtr, 0, calldatasize())

            // The msg.sender address is shifted to the left by 12 bytes to remove the padding
            // Then the address without padding is stored right after the calldata
            let senderPtr := allocate(20)
            mstore(senderPtr, shl(96, caller()))

            // Add 20 bytes for the address appended add the end
            let success := call(gas(), handler, 0, calldataPtr, add(calldatasize(), 20), 0, 0)

            let returnDataPtr := allocate(returndatasize())
            returndatacopy(returnDataPtr, 0, returndatasize())
            if iszero(success) {
                revert(returnDataPtr, returndatasize())
            }
            return(returnDataPtr, returndatasize())
        }
    }

    receive() external payable {}
}
