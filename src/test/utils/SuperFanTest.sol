// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;
import "ds-test/test.sol";

import "../../SuperFan.sol";
import "./Hevm.sol";

abstract contract SuperFanTest is DSTest {
    Hevm internal constant hevm = Hevm(HEVM_ADDRESS);

    // contracts
    SuperFan internal superfan;

    string name = "SuperFan";
    string symbol = "SUB";

    // goerli
    ISuperfluid host = ISuperfluid(0x22ff293e14F1EC3A09B137e9e06084AFd63adDF9);
    IConstantFlowAgreementV1 cfa = IConstantFlowAgreementV1(0xEd6BcbF6907D4feEEe8a8875543249bEa9D308E8);
    ISuperToken token = ISuperToken(0xF2d68898557cCb2Cf4C10c3Ef2B034b2a69DAD00); // fdaix

    // users
    address alice = 0xa000000000000000000000000000000000000000;
    address bob = 0xB000000000000000000000000000000000000000;

    function setUp() public virtual {
        superfan = new SuperFan(name, symbol, host, cfa, token);
    }
}
