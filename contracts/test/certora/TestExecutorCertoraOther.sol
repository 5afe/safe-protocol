// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.18;
import {TestExecutorCertora} from "../TestExecutorCertora.sol";

contract TestExecutorCertoraOther is TestExecutorCertora {
    constructor(address _fallbackHandler) TestExecutorCertora(_fallbackHandler) {}
}
