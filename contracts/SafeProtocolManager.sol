// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.18;
import {ISafeProtocolPlugin, ISafeProtocolHooks} from "./interfaces/Modules.sol";

import {IAccount} from "./interfaces/Accounts.sol";
import {SafeProtocolAction, SafeTransaction, SafeRootAccess} from "./DataTypes.sol";
import {ISafeProtocolRegistry} from "./interfaces/Registry.sol";
import {RegistryManager} from "./base/RegistryManager.sol";
import {HooksManager} from "./base/HooksManager.sol";
import {FunctionHandlerManager} from "./base/FunctionHandlerManager.sol";
import {ISafeProtocolManager} from "./interfaces/Manager.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {Enum} from "./common/Enum.sol";
import {PLUGIN_PERMISSION_NONE, PLUGIN_PERMISSION_EXECUTE_CALL, PLUGIN_PERMISSION_CALL_TO_SELF, PLUGIN_PERMISSION_EXECUTE_DELEGATECALL} from "./common/Constants.sol";
import {MODULE_TYPE_PLUGIN} from "./common/Constants.sol";

/**
 * @title SafeProtocolManager contract allows users of Accounts compatible with the Safe{Core} Protocol to enable
 *        plugins through a Manager rather than directly enabling plugins in their Account.
 *        Users have to first enable SafeProtocolManager as a plugin on their Account and then enable other plugins through the manager.
 */
contract SafeProtocolManager is ISafeProtocolManager, RegistryManager, HooksManager, FunctionHandlerManager, IERC165 {
    address internal constant SENTINEL_MODULES = address(0x1);

    /**
     * @notice Mapping of a mapping what stores information about plugins that are enabled per account.
     *         address (module address) => address (account address) => EnabledPluginInfo
     * @dev The key of the inner-most mapping is the account address, which is required for 4337-compatibility.
     */
    mapping(address => mapping(address => PluginAccessInfo)) public enabledPlugins;
    struct PluginAccessInfo {
        uint8 permissions;
        address nextPluginPointer;
    }

    // Events
    event ActionsExecuted(address indexed account, bytes32 metadataHash, uint256 nonce);
    event RootAccessActionExecuted(address indexed account, bytes32 metadataHash);
    event PluginEnabled(address indexed account, address indexed plugin, uint8 permissions);
    event PluginDisabled(address indexed account, address indexed plugin);

    // Errors
    error PluginNotEnabled(address plugin);
    error MissingPluginPermission(address plugin, uint8 pluginRequires, uint8 requiredPermission, uint8 givenPermission);
    error PluginPermissionsMismatch(address plugin, uint8 requiredPermissions, uint8 givenPermissions);
    error ActionExecutionFailed(address account, bytes32 metadataHash, uint256 index);
    error RootAccessActionExecutionFailed(address account, bytes32 metadataHash);
    error PluginAlreadyEnabled(address account, address plugin);
    error InvalidPluginAddress(address plugin);
    error InvalidPrevPluginAddress(address plugin);
    error ZeroPageSizeNotAllowed();
    error InvalidToFieldInSafeProtocolAction(address account, bytes32 metadataHash, uint256 index);

    modifier onlyEnabledPlugin(address account) {
        checkOnlyEnabledPlugin(account);
        _;
    }

    modifier noZeroOrSentinelPlugin(address plugin) {
        checkNoZeroOrSentinelPlugin(plugin);
        _;
    }

    constructor(address initialOwner, address _registry) RegistryManager(_registry, initialOwner) {}

    /**
     * @notice This function executes non-delegate call(s) on an account if the plugin is enabled for the Account.
     *         If any one of the actions fail, the transaction reverts.
     * @dev Restrict the `to` field in the actions so that a module cannot execute an action that changes the config such as
     *      enabling/disabling other modules or make changes to its own access level for an account.
     *      In future, evaluate use of fine granined permissions model executing actions.
     *      For more information, follow the disuccsion here: https://github.com/safe-global/safe-core-protocol-specs/discussions/7.
     * @param account Target account address
     * @param transaction A struct of type SafeTransaction containing information of about the action(s) to be executed.
     *                    Users can add logic to validate metadataHash through hooks.
     * @return data bytes types containing the result of the executed action.
     */
    function executeTransaction(
        address account,
        SafeTransaction calldata transaction
    ) external override onlyEnabledPlugin(account) onlyPermittedModule(msg.sender, MODULE_TYPE_PLUGIN) returns (bytes[] memory data) {
        address hooksAddress = enabledHooks[account];
        bool areHooksEnabled = hooksAddress != address(0);
        bytes memory preCheckData;
        if (areHooksEnabled) {
            // execution metadata for transaction execution through plugin is encoded address of the plugin i.e. msg.sender.
            // executionType = 1 for plugin flow
            // should check below exist here?
            checkPermittedModule(hooksAddress);
            preCheckData = ISafeProtocolHooks(hooksAddress).preCheck(account, transaction, 1, abi.encode(msg.sender));
        }

        data = new bytes[](transaction.actions.length);
        uint256 length = transaction.actions.length;
        for (uint256 i = 0; i < length; ++i) {
            SafeProtocolAction calldata safeProtocolAction = transaction.actions[i];

            if (safeProtocolAction.to == address(this)) {
                revert InvalidToFieldInSafeProtocolAction(account, transaction.metadataHash, i);
            } else if (safeProtocolAction.to == account) {
                checkPermission(account, PLUGIN_PERMISSION_CALL_TO_SELF);
            } else {
                checkPermission(account, PLUGIN_PERMISSION_EXECUTE_CALL);
            }

            (bool isActionSuccessful, bytes memory resultData) = IAccount(account).execTransactionFromModuleReturnData(
                safeProtocolAction.to,
                safeProtocolAction.value,
                safeProtocolAction.data,
                0
            );

            // Even if one action fails, revert the transaction.
            if (!isActionSuccessful) {
                revert ActionExecutionFailed(account, transaction.metadataHash, i);
            } else {
                data[i] = resultData;
            }
        }
        if (areHooksEnabled) {
            // success = true because if transaction is not revereted till here, all actions executed successfully.
            ISafeProtocolHooks(hooksAddress).postCheck(account, true, preCheckData);
        }
        emit ActionsExecuted(account, transaction.metadataHash, transaction.nonce);
    }

    /**
     * @notice This function executes a delegate call on an account if the plugin is enabled and
     *         the root access is granted.
     * @param account Target account address
     * @param rootAccess A struct of type SafeRootAccess containing information of about the action to be executed.
     *                   Users can add logic to validate metadataHash through hooks.
     * @return data bytes types containing the result of the executed action.
     */
    function executeRootAccess(
        address account,
        SafeRootAccess calldata rootAccess
    ) external override onlyEnabledPlugin(account) onlyPermittedModule(msg.sender, MODULE_TYPE_PLUGIN) returns (bytes memory data) {
        SafeProtocolAction calldata safeProtocolAction = rootAccess.action;

        address hooksAddress = enabledHooks[account];
        bool areHooksEnabled = hooksAddress != address(0);
        bytes memory preCheckData;
        if (areHooksEnabled) {
            // execution metadata for transaction execution through plugin is encoded address of the plugin i.e. msg.sender.
            // executionType = 1 for plugin flow
            // should check below exist here?
            checkPermittedModule(hooksAddress);
            preCheckData = ISafeProtocolHooks(hooksAddress).preCheckRootAccess(account, rootAccess, 1, abi.encode(msg.sender));
        }

        checkPermission(account, PLUGIN_PERMISSION_EXECUTE_DELEGATECALL);

        bool success;
        (success, data) = IAccount(account).execTransactionFromModuleReturnData(
            safeProtocolAction.to,
            safeProtocolAction.value,
            safeProtocolAction.data,
            1
        );

        if (areHooksEnabled) {
            // success = true because if transaction is not revereted till here, all actions executed successfully.
            ISafeProtocolHooks(hooksAddress).postCheck(account, success, preCheckData);
        }

        if (success) {
            emit RootAccessActionExecuted(account, rootAccess.metadataHash);
        } else {
            revert RootAccessActionExecutionFailed(account, rootAccess.metadataHash);
        }
    }

    /**
     * @notice Enables a plugin for an account. Must be called by the account.
     * @param plugin ISafeProtocolPlugin A plugin that has to be enabled
     * @param permissions uint8 indicating permissions granted to the plugin.
     */
    function enablePlugin(
        address plugin,
        uint8 permissions
    ) external noZeroOrSentinelPlugin(plugin) onlyPermittedModule(plugin, MODULE_TYPE_PLUGIN) onlyAccount {
        // address(0) check omitted because it is not expected to enable it as a plugin and
        // call to it would fail. Additionally, registry should not permit address(0) as an module.
        if (!ISafeProtocolPlugin(plugin).supportsInterface(type(ISafeProtocolPlugin).interfaceId))
            revert ContractDoesNotImplementValidInterfaceId(plugin);

        PluginAccessInfo storage senderSentinelPlugin = enabledPlugins[SENTINEL_MODULES][msg.sender];
        PluginAccessInfo storage senderPlugin = enabledPlugins[plugin][msg.sender];

        if (senderPlugin.nextPluginPointer != address(0)) {
            revert PluginAlreadyEnabled(msg.sender, plugin);
        }

        uint8 requiresPermissions = ISafeProtocolPlugin(plugin).requiresPermissions();
        if (permissions != requiresPermissions) {
            revert PluginPermissionsMismatch(plugin, requiresPermissions, permissions);
        }

        if (senderSentinelPlugin.nextPluginPointer == address(0)) {
            senderSentinelPlugin.nextPluginPointer = SENTINEL_MODULES;
        }

        senderPlugin.nextPluginPointer = senderSentinelPlugin.nextPluginPointer;
        senderPlugin.permissions = permissions;
        senderSentinelPlugin.nextPluginPointer = plugin;

        emit PluginEnabled(msg.sender, plugin, permissions);
    }

    /**
     * @notice Disable a plugin. This function should be called by account.
     * @param plugin Plugin to be disabled
     */
    function disablePlugin(address prevPlugin, address plugin) external noZeroOrSentinelPlugin(plugin) onlyAccount {
        PluginAccessInfo storage prevPluginInfo = enabledPlugins[prevPlugin][msg.sender];
        PluginAccessInfo storage pluginInfo = enabledPlugins[plugin][msg.sender];

        if (prevPluginInfo.nextPluginPointer != plugin) {
            revert InvalidPrevPluginAddress(prevPlugin);
        }

        prevPluginInfo.nextPluginPointer = pluginInfo.nextPluginPointer;
        prevPluginInfo.permissions = pluginInfo.permissions;

        pluginInfo.nextPluginPointer = address(0);
        pluginInfo.permissions = PLUGIN_PERMISSION_NONE;
        emit PluginDisabled(msg.sender, plugin);
    }

    /**
     * @notice A view only function to get information about an account and a plugin
     * @param account Address of an account
     * @param plugin Address of a plugin
     */
    function getPluginInfo(address account, address plugin) external view returns (PluginAccessInfo memory enabled) {
        return enabledPlugins[plugin][account];
    }

    /**
     * @notice Returns if an plugin is enabled
     * @param account Address of an account
     * @param plugin Address of a plugin
     * @return True if the plugin is enabled
     */
    function isPluginEnabled(address account, address plugin) public view returns (bool) {
        return SENTINEL_MODULES != plugin && enabledPlugins[plugin][account].nextPluginPointer != address(0);
    }

    /**
     * @notice Returns an array of plugins enabled for an account address.
     *         If all entries fit into a single page, the next pointer will be 0x1.
     *         If another page is present, next will be the last element of the returned array.
     * @param start Start of the page. Has to be a plugin or start pointer (0x1 address)
     * @param pageSize Maximum number of plugins that should be returned. Has to be > 0
     * @return array Array of plugins.
     * @return next Start of the next page.
     */
    function getPluginsPaginated(
        address start,
        uint256 pageSize,
        address account
    ) external view returns (address[] memory array, address next) {
        if (pageSize == 0) {
            revert ZeroPageSizeNotAllowed();
        }

        if (!(start == SENTINEL_MODULES || isPluginEnabled(account, start))) {
            revert InvalidPluginAddress(start);
        }
        // Init array with max page size
        array = new address[](pageSize);

        // Populate return array
        uint256 pluginCount = 0;
        next = enabledPlugins[start][account].nextPluginPointer;
        while (next != address(0) && next != SENTINEL_MODULES && pluginCount < pageSize) {
            array[pluginCount] = next;
            next = enabledPlugins[next][account].nextPluginPointer;
            pluginCount++;
        }

        // This check is required because the enabled plugin list might not be initialised yet. e.g. no enabled plugins for an account ever before
        if (pluginCount == 0) {
            next = SENTINEL_MODULES;
        }

        /**
          Because of the argument validation, we can assume that the loop will always iterate over the valid plugin list values
          and the `next` variable will either be an enabled plugin or a sentinel address (signalling the end).

          If we haven't reached the end inside the loop, we need to set the next pointer to the last element of the plugins array
          because the `next` variable (which is a plugin by itself) acting as a pointer to the start of the next page is neither
          included to the current page, nor will it be included in the next one if you pass it as a start.
        */
        if (next != SENTINEL_MODULES && pluginCount != 0) {
            next = array[pluginCount - 1];
        }
        // Set correct size of returned array
        // solhint-disable-next-line no-inline-assembly
        assembly {
            mstore(array, pluginCount)
        }
    }

    /**
     * @notice Implement BaseGuard interface to allow an account to add Manager as a guard for existing Safe accounts (upto version 1.5.x).
     * @dev An account must enable SafeProtocolManager as a Guard (for Safe v1.x) and enable a contract address as Hooks.
     *      If there is no hooks enabled for the Safe, transaction will pass through without any checks.
     * @param to address of the account
     * @param value Amount of ETH to be sent
     * @param data Artibtrary length bytes containing payload
     * @param operation Call or DelegateCall operation
     * @param safeTxGas uint256
     * @param baseGas uint256
     * @param gasPrice uint256
     * @param gasToken address
     * @param refundReceiver payable address
     * @param signatures Arbitrary bytes containing ECDSA signatures
     * @param msgSender Sender of the transaction
     */
    function checkTransaction(
        address to,
        uint256 value,
        bytes memory data,
        Enum.Operation operation,
        uint256 safeTxGas,
        uint256 baseGas,
        uint256 gasPrice,
        address gasToken,
        address payable refundReceiver,
        bytes memory signatures,
        address msgSender
    ) external {
        // Store hooks address in tempHooksAddress so that checkAfterExecution(...) can access it.
        // A temprary storage is required to use old hooks in checkAfterExecution if hooks get updated in between transaction
        tempHooksData[msg.sender].hooksAddress = enabledHooks[msg.sender];
        address tempHooksAddressForAccount = enabledHooks[msg.sender];

        if (tempHooksAddressForAccount == address(0)) return;
        bytes memory executionMetadata = abi.encode(
            to,
            value,
            data,
            safeTxGas,
            baseGas,
            gasPrice,
            gasToken,
            refundReceiver,
            signatures,
            msgSender
        );

        if (operation == Enum.Operation.Call) {
            SafeProtocolAction[] memory actions = new SafeProtocolAction[](1);
            actions[0] = SafeProtocolAction(payable(to), value, data);
            SafeTransaction memory safeTx = SafeTransaction(actions, 0, "");
            tempHooksData[msg.sender].preCheckData = ISafeProtocolHooks(tempHooksAddressForAccount).preCheck(
                msg.sender,
                safeTx,
                0,
                executionMetadata
            );
        } else {
            // Using else instead of "else if(operation == Enum.Operation.DelegateCall)" to reduce gas usage
            // because accounts must only allow Call and DelegateCall operations.
            SafeProtocolAction memory action = SafeProtocolAction(payable(to), value, data);
            SafeRootAccess memory safeTx = SafeRootAccess(action, 0, "");
            tempHooksData[msg.sender].preCheckData = ISafeProtocolHooks(tempHooksAddressForAccount).preCheckRootAccess(
                msg.sender,
                safeTx,
                0,
                executionMetadata
            );
        }
    }

    /**
     * @notice Implement BaseGuard interface to allow Safe to add Manager as a guard for existing Safe accounts (upto version 1.5.x).
     * @param success bool
     */
    function checkAfterExecution(bytes32, bool success) external {
        address tempHooksAddressForAccount = tempHooksData[msg.sender].hooksAddress;
        if (tempHooksAddressForAccount == address(0)) return;

        // Use tempHooksAddress to avoid a case where hooks get updated in the middle of a transaction.
        ISafeProtocolHooks(tempHooksAddressForAccount).postCheck(msg.sender, success, tempHooksData[msg.sender].preCheckData);

        // Reset to address(0) so that there is no unattended storage
        tempHooksData[msg.sender].hooksAddress = address(0);
        tempHooksData[msg.sender].preCheckData = bytes("");
    }

    /**
     * @notice This function is introduced in Safe contracts v1.5 and used for checking module transactions when a guard is enabled.
     *         This function will be called when executing a transaction from a module with Safe v1.5 and Manager enabled as Guard on Safe.
     * @param to The address to which the transaction is intended.
     * @param value The value of the transaction in Wei.
     * @param data The transaction data.
     * @param operation The type of operation of the transaction.
     * @param module The module involved in the transaction.
     * @return moduleTxHash The hash of the module transaction.
     */
    function checkModuleTransaction(
        address to,
        uint256 value,
        bytes memory data,
        Enum.Operation operation,
        address module /* onlyPermittedPlugin(module) uncomment this? */ // Use term plugin?
    ) external returns (bytes32 moduleTxHash) {
        // Store hooks address in tempHooksAddress so that checkAfterExecution(...) can access it.
        // A temprary storage is required to use old hooks in checkAfterExecution if hooks get updated in between transaction
        tempHooksData[msg.sender].hooksAddress = enabledHooks[msg.sender];
        address tempHooksAddressForAccount = enabledHooks[msg.sender];

        moduleTxHash = keccak256(abi.encode(to, value, data, operation, module));
        if (tempHooksAddressForAccount == address(0)) return moduleTxHash;

        if (operation == Enum.Operation.Call) {
            SafeProtocolAction[] memory actions = new SafeProtocolAction[](1);
            actions[0] = SafeProtocolAction(payable(to), value, data);
            SafeTransaction memory safeTx = SafeTransaction(actions, 0, "");
            ISafeProtocolHooks(tempHooksAddressForAccount).preCheck(msg.sender, safeTx, 1, abi.encode(module));
        } else {
            // Using else instead of "else if(operation == Enum.Operation.DelegateCall)" to reduce gas usage
            // and Safe allows only Call and DelegateCall operations.
            SafeProtocolAction memory action = SafeProtocolAction(payable(to), value, data);
            SafeRootAccess memory safeTx = SafeRootAccess(action, 0, "");
            ISafeProtocolHooks(tempHooksAddressForAccount).preCheckRootAccess(msg.sender, safeTx, 1, abi.encode(module));
        }

        return moduleTxHash;
    }

    function supportsInterface(bytes4 interfaceId) external view virtual override returns (bool) {
        return
            interfaceId == 0x945b8148 || // type(Guard).interfaceId with Module Guard
            interfaceId == 0xe6d7a83a || // type(Guard).interfaceId without Module Guard (required for backward compatibility for Safe v1.4 and below)
            interfaceId == type(ISafeProtocolManager).interfaceId ||
            interfaceId == type(IERC165).interfaceId; // 0x01ffc9a7
    }

    function checkOnlyEnabledPlugin(address account) private view {
        if (enabledPlugins[msg.sender][account].nextPluginPointer == address(0)) {
            revert PluginNotEnabled(msg.sender);
        }
    }

    function checkNoZeroOrSentinelPlugin(address plugin) private pure {
        if (plugin == address(0) || plugin == SENTINEL_MODULES) {
            revert InvalidPluginAddress(plugin);
        }
    }

    /**
     * @notice Checks if the caller i.e. plugin has the required permission for the given account.
     *         The function reverts if the plugin does not have the required permission or required by the plugin
     *         permissions do not match expected permission.
     * @param account Address of the account for which the permission is checked for
     * @param permission Permission that is required. Value can be one of the following: PLUGIN_PERMISSION_EXECUTE_CALL,
     *        PLUGIN_PERMISSION_CALL_TO_SELF, or PLUGIN_PERMISSION_EXECUTE_DELEGATECALL.
     */
    function checkPermission(address account, uint8 permission) private view {
        // For each action, Manager will read storage and call plugin's requiresPermissions().
        uint8 givenPermissions = enabledPlugins[msg.sender][account].permissions;
        uint8 requiresPermissions = ISafeProtocolPlugin(msg.sender).requiresPermissions();

        if ((requiresPermissions & givenPermissions & permission) != permission) {
            revert MissingPluginPermission(msg.sender, requiresPermissions, permission, givenPermissions);
        }
    }
}
