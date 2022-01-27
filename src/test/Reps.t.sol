// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.10;

import {DSTestPlus} from "solmate/test/utils/DSTestPlus.sol";
import {ERC20User} from "solmate/test/utils/users/ERC20User.sol";
import {WETH} from "solmate/tokens/WETH.sol";
import {CentralizedArbitrator} from "./CentralizedArbitrator.sol";
import {Reps} from "../Reps.sol";
import {Rep, IRep} from "../Rep.sol";
import {Hevm} from "./Hevm.sol";

contract RepsTest is DSTestPlus {
    event Transfer(
        address indexed from,
        address indexed to,
        uint256 indexed id
    );

    event TransferETH(address to, uint256 value, bool success);

    event Checkpoint(uint256 rep, uint256 claimable, uint256 streaming);

    // Using these events it is possible to process the events to build up reverse lookups.
    // The indeces allow it to be very partial about how to build this lookup (e.g. only for a specific rep).
    event SetRep(
        address indexed delegator,
        bytes32 indexed id,
        uint256 indexed rep
    );
    event ClearRep(
        address indexed delegator,
        bytes32 indexed id,
        uint256 indexed rep
    );

    Hevm vm = Hevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);
    Reps reps;
    WETH weth;
    CentralizedArbitrator arb;
    string name = "Test";
    string symbol = "TST";
    string uri = "uri";
    bytes32 hash_ = keccak256("I promise to be good");
    address alice = address(0xBEEF);
    address bob = address(0xFEEB);

    function setUp() public {
        weth = new WETH();

        reps = new Reps(name, symbol, address(weth));
        assertEq(reps.name(), name, "name");
        assertEq(reps.symbol(), symbol, "symbol");
        assertEq(reps.weth(), address(weth), "weth");

        arb = new CentralizedArbitrator(1000000, 10000, 2000000);
    }

    function checkPaymentData(
        uint256 rep,
        uint256 checkpoint_,
        uint256 claimable_,
        uint256 pool_,
        uint256 rate_
    ) public {
        (
            uint256 checkpoint,
            uint256 claimable,
            uint256 pool,
            uint256 rate
        ) = reps.repPaymentData(rep);
        assertEq(checkpoint, checkpoint_, "checkpoint");
        assertEq(claimable, claimable_, "claimable");
        assertEq(pool, pool_, "pool");
        assertEq(rate, rate_, "rate");
    }

    function checkDisputeData(
        uint256 rep,
        uint256 disputeId_,
        address disputeCreator_
    ) public {
        (address arbitrator, uint256 disputeId, address disputeCreator) = reps
            .repDisputeData(rep);
        assertEq(arbitrator, address(arb), "arbitrator");
        assertEq(disputeId, disputeId_, "disputeId");
        assertEq(disputeCreator, disputeCreator_, "disputeCreator");
    }

    //===== newRep =====//

    function testNewRep(address owner_) public returns (uint256 rep) {
        uint256 count = reps.repCount();
        vm.expectEmit(true, true, true, false);
        emit Transfer(address(0), owner_, count + 1);
        rep = reps.newRep(owner_, uri, hash_, address(arb));
        assertEq(reps.repCount(), count + 1, "count");
        assertEq(reps.ownerOf(rep), owner_, "owner");
        assertEq(reps.tokenURI(rep), uri, "uri");
        assertEq(reps.promiseHash(rep), hash_, "hash");

        checkPaymentData(rep, 0, 0, 0, 0);
        checkDisputeData(rep, 0, address(0));
    }

    //===== setRep =====//

    function testSetRep() public returns (uint256 rep, bytes32 delegationId) {
        rep = testNewRep(alice);
        uint256 payment = 1 ether;
        delegationId = keccak256("gov id");
        vm.expectEmit(true, true, true, false);
        emit SetRep(address(this), delegationId, rep);
        reps.setRep{value: payment}(delegationId, rep);
        assertEq(reps.delegation(address(this), delegationId), rep, "rep");

        checkPaymentData(rep, 0, 0, payment, payment);
    }

    function testSetRep_fromRep() public {
        (uint256 rep, bytes32 delegationId) = testSetRep();
        uint256 rep2 = testNewRep(bob);
        uint256 payment = 1 ether;
        delegationId = keccak256("gov id");
        vm.expectEmit(true, true, true, false);
        emit SetRep(address(this), delegationId, rep2);
        reps.setRep{value: payment}(delegationId, rep2);
        assertEq(reps.delegation(address(this), delegationId), rep2, "rep2");

        checkPaymentData(rep2, 0, 0, payment, payment);
    }

    function testFailSetRep_NoRep() public {
        uint256 payment = 1 ether;
        bytes32 delegationId = keccak256("gov id");
        reps.setRep{value: payment}(delegationId, 1);
    }

    function testFailSetRep_RepOwnerIsSender() public {
        uint256 rep = testNewRep(address(this));
        uint256 payment = 1 ether;
        bytes32 delegationId = keccak256("gov id");
        reps.setRep{value: payment}(delegationId, rep);
    }

    function testFailSetRep_AlreadySet() public {
        (uint256 rep, bytes32 delegationId) = testSetRep();
        reps.setRep{value: 1 ether}(delegationId, rep);
    }

    //===== clearRep =====//

    function testClearRep() public {
        (uint256 rep, bytes32 delegationId) = testSetRep();
        vm.expectEmit(true, true, true, false);
        emit ClearRep(address(this), delegationId, rep);
        reps.clearRep(delegationId);
        assertEq(
            reps.delegation(address(this), delegationId),
            0,
            "cleared rep"
        );
    }
}
