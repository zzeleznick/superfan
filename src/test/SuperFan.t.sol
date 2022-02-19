// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "./utils/SuperFanTest.sol";
import {Errors} from "../SuperFan.sol";

contract BasicTest is SuperFanTest {

    function testCannotSubscribe() public {
        try superfan._subscribe(alice, 1) {
            fail();
        } catch Error(string memory error) {
            assertEq(error, Errors.TierOwnerMismatch);
        }
    }

    function testCreateTier() public {
        assertEq(superfan.nextTierId(), uint(1));
        superfan.createTier(38580246913580); // $100 per mo
        assertEq(superfan.nextTierId(), uint(2));
        superfan.createTier(385802469135800); // $1000 per mo
        assertEq(superfan.nextTierId(), uint(3));
    }
}
