using SafeProtocolRegistry as contractRegistry;
using TestExecutorCertora as testExecutorCertora;
using TestFunctionHandlerCertora as testFunctionHandlerCertora;
using TestHooksCertora as testHooksCertora;
using TestExecutorCertoraOther as testExecutorCertoraOther;
using TestPlugin as testPlugin;

methods {
    function setRegistry(address) external;
    function registry() external returns (address) envfree;
    function tempHooksData(address) external returns (address, bytes) envfree;

    function _.supportsInterface(bytes4) external => DISPATCHER(true);
    function testExecutorCertora.called() external returns (bool) envfree;

    function contractRegistry.check(address module) external returns (uint64, uint64) envfree;
    function _.execTransactionFromModule(
        address,
        uint256,
        bytes,
        uint8 
    ) external => DISPATCHER(true);

    function _.execTransactionFromModuleReturnData(
        address,
        uint256,
        bytes,
        uint8 
    )  external => DISPATCHER(true);

    function _.preCheck(
        address,
        SafeProtocolManager.SafeTransaction,
        uint256,
        bytes 
    ) external => DISPATCHER(true);

    function _.preCheckRootAccess(
        address,
        SafeProtocolManager.SafeRootAccess,
        uint256,
        bytes
    ) external => DISPATCHER(true);

    function _.postCheck(address, bool, bytes) external => DISPATCHER(true);

    function _.handle(address, address, uint256, bytes) external => DISPATCHER(true);

    function testFunctionHandlerCertora.called() external returns (bool) envfree;

    function testHooksCertora.called() external returns (bool) envfree;

    function _.requiresPermissions() external => DISPATCHER(true);
}

rule onlyOwnerCanSetRegistry (method f) filtered {
    f -> f.selector != sig:setRegistry(address).selector
}
{
    address registryBefore = registry();

    calldataarg args; env e;
    f(e, args);

    address registryAfter = registry();

    assert registryBefore == registryAfter;

}

rule onlyEnabledAndListedPluginCanExecuteCall(method f) filtered {
    f -> f.selector == sig:executeTransaction(address,SafeProtocolManager.SafeTransaction).selector || f.selector == sig:executeRootAccess(address,SafeProtocolManager.SafeRootAccess).selector 
} {

    env e; calldataarg args;

    requireInvariant tempHooksStorage(e.msg.sender);

    require(testExecutorCertora.called() == false);
    require(testFunctionHandlerCertora.called() == false);
    require(testHooksCertora.called() == false);

    f(e, args);

    uint64 listedAt;
    uint64 flagged;

    listedAt, flagged = contractRegistry.check(e.msg.sender);

    assert testExecutorCertora.called() => (listedAt > 0 && flagged == 0);

    uint64 listedAtHandler;
    uint64 flaggedHandler;

    listedAtHandler, flaggedHandler = contractRegistry.check(testFunctionHandlerCertora);

    assert testFunctionHandlerCertora.called() => (listedAtHandler > 0 && flaggedHandler == 0);


    uint64 listedAtHooks;
    uint64 flaggedHooks;

    listedAtHooks, flaggedHooks = contractRegistry.check(testHooksCertora);

    assert testHooksCertora.called() => (listedAtHooks > 0 && flaggedHooks == 0);

}

rule hooksUpdates(address safe, SafeProtocolManager.SafeTransaction transactionData){

    // method f;
    env e; calldataarg args;
    storage initialStorage = lastStorage;
    executeTransaction(e, safe, transactionData);

    env e2;
    setHooks(e2, 0) at initialStorage;

    executeTransaction@withrevert(e, safe, transactionData);

    assert !lastReverted;

}

function checkListedAndNotFlagged(address module) returns bool {
    uint64 listedAtHooks;
    uint64 flaggedHooks;
    listedAtHooks, flaggedHooks = contractRegistry.check(module);
    return (listedAtHooks > 0 && flaggedHooks == 0);
}

function getTempHooksData(address account) returns address {
    address hooksAddress;
    bytes hooksData;
    hooksAddress, hooksData = tempHooksData(account);
    return hooksAddress;
}

invariant tempHooksStorage(address plugin) 
    getTempHooksData(plugin) != 0 => checkListedAndNotFlagged(getTempHooksData(plugin))
    filtered { f -> f.selector != sig:checkModuleTransaction(address,uint256,bytes,Enum.Operation,address).selector}

invariant tempHooksStorageIsAlwaysEmpty(address plugin) 
    getTempHooksData(plugin) == 0
    filtered { f -> f.selector != sig:checkModuleTransaction(address,uint256,bytes,Enum.Operation,address).selector}


rule onlyOneStorageUpdates{
    storage before = lastStorage;
    method f; env e; calldataarg args;
    f(e, args);
    storage after = lastStorage;
    // Either storage of testExecutorCertora is updated or storage of testExecutorCertoraOther is updated
    assert (before[testExecutorCertora] == after[testExecutorCertora]) || (before[testExecutorCertoraOther] == after[testExecutorCertoraOther]);
}
