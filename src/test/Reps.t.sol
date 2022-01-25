// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.10;

import {DSTestPlus} from "solmate/test/utils/DSTestPlus.sol";
import {ERC20User} from "solmate/test/utils/users/ERC20User.sol";
import {WETH} from "solmate/tokens/WETH.sol";
import {CentralizedArbitrator} from "./CentralizedArbitrator.sol";
import {Reps} from "../Reps.sol";
import {Rep, IRep} from "../Rep.sol";
import "./console.sol";

contract RepsTest is DSTestPlus {
    Reps reps;
    WETH weth;
    CentralizedArbitrator arb;

    function setUp() public {
        weth = new WETH();
        reps = new Reps("Test", "TST", address(weth));
        arb = new CentralizedArbitrator(1000000, 10000, 2000000);
    }

    function testMetaData() public {
        assertEq(reps.name(), "Test");
        assertEq(reps.symbol(), "TST");
        assertEq(reps.weth(), address(weth));
    }

    function testNewRep() public {
        uint256 rep = reps.newRep(
            address(0xBEEF),
            "uri",
            keccak256("I promise to be good"),
            address(arb)
        );
        assertEq(reps.ownerOf(rep), address(0xBEEF));
    }
}
