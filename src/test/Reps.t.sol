// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.10;

import {DSTestPlus} from "solmate/test/utils/DSTestPlus.sol";
import {ERC20User} from "solmate/test/utils/users/ERC20User.sol";
import {WETH} from "solmate/tokens/WETH.sol";
import {CentralizedArbitrator} from "./CentralizedArbitrator.sol";
import {IArbitrable} from "../IArbitrable.sol";
import {IArbitrator} from "../IArbitrator.sol";
import {Reps} from "../Reps.sol";
import {Hevm} from "./Hevm.sol";
import "./console.sol";

contract RepsTest is DSTestPlus {
    event Transfer(
        address indexed from,
        address indexed to,
        uint256 indexed id
    );

    event TransferETH(address to, uint256 value, bool success);

    event Checkpoint(uint256 rep, uint256 claimable, uint256 streaming);

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

    event DisputeCreation(
        uint256 indexed _disputeID,
        IArbitrable indexed _arbitrable
    );

    event Ruling(
        IArbitrator indexed _arbitrator,
        uint256 indexed _disputeID,
        uint256 _ruling
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

    function testSetRep(uint64 payment)
        public
        returns (uint256 rep, bytes32 delegationId)
    {
        // set up rep
        rep = testNewRep(alice);
        delegationId = keccak256("gov id");

        // delegate to rep
        vm.expectEmit(true, true, true, false);
        emit SetRep(address(this), delegationId, rep);
        reps.setRep{value: payment}(delegationId, rep);
        assertEq(reps.delegation(address(this), delegationId), rep, "rep");

        checkPaymentData(rep, 0, 0, payment, payment);
    }

    function testSetRep_fromRep(uint64 payment1, uint64 payment2) public {
        // set up rep with delegation
        (uint256 rep, bytes32 delegationId) = testSetRep(payment1);
        uint256 rep2 = testNewRep(bob);
        delegationId = keccak256("gov id");

        // set to new rep from old rep
        vm.expectEmit(true, true, true, false);
        emit SetRep(address(this), delegationId, rep2);
        reps.setRep{value: payment2}(delegationId, rep2);
        assertEq(reps.delegation(address(this), delegationId), rep2, "rep2");

        checkPaymentData(rep2, 0, 0, payment2, payment2);
    }

    function testFailSetRep_NoRep(uint64 payment) public {
        bytes32 delegationId = keccak256("gov id");
        reps.setRep{value: payment}(delegationId, 1);
    }

    function testFailSetRep_RepOwnerIsSender(uint64 payment) public {
        uint256 rep = testNewRep(address(this));
        bytes32 delegationId = keccak256("gov id");
        reps.setRep{value: payment}(delegationId, rep);
    }

    function testFailSetRep_AlreadySet(uint64 payment) public {
        (uint256 rep, bytes32 delegationId) = testSetRep(payment);
        reps.setRep{value: payment}(delegationId, rep);
    }

    //===== clearRep =====//

    function testClearRep() public {
        // set up rep
        (uint256 rep, bytes32 delegationId) = testSetRep(1 ether);

        // clear rep
        vm.expectEmit(true, true, true, false);
        emit ClearRep(address(this), delegationId, rep);
        reps.clearRep(delegationId);
        assertEq(
            reps.delegation(address(this), delegationId),
            0,
            "cleared rep"
        );
    }

    function testFailClearRep_NoRep() public {
        bytes32 delegationId = keccak256("gov id");
        reps.clearRep(delegationId);
    }

    //===== boostEthFor =====//

    function testBoostEthFor(uint64 payment, uint64 time)
        public
        returns (uint256 rep)
    {
        // set up rep
        rep = testNewRep(alice);
        (
            uint256 checkpoint,
            uint256 claimable,
            uint256 pool,
            uint256 rate
        ) = reps.repPaymentData(rep);

        // fast forward
        uint256 newTime = checkpoint + time;
        uint256 newClaimable = reps.claimableAt(rep, newTime);
        vm.warp(newTime);

        // boost
        uint256 newPool = pool + payment;
        vm.expectEmit(false, false, false, true);
        emit Checkpoint(rep, newClaimable, newPool);
        reps.boostEthFor{value: payment}(rep);
        checkPaymentData(rep, newTime, newClaimable, newPool, rate + payment);
    }

    //===== claimableAt =====//

    function testClaimableAt(uint256 time) public {
        uint256 rep = testNewRep(alice);
        (uint256 checkpoint, , uint256 pool, uint256 rate) = reps
            .repPaymentData(rep);
        uint256 newTime = checkpoint + time;
        uint256 claimable = reps.claimableAt(rep, newTime);
        assertEq(claimable, (rate * time) / 365 days, "claimable");
    }

    function testClaimableAt_NonexistentRep(uint256 time) public {
        uint256 newTime = block.timestamp + time;
        uint256 claimable = reps.claimableAt(1, newTime);
        assertEq(claimable, 0, "claimable");
    }

    //===== claimFor =====//

    function testClaimFor(
        uint64 payment,
        uint64 time1,
        uint64 time2
    ) public {
        // set up rep with payment
        uint256 rep = testBoostEthFor(payment, time1);
        uint256 repsBalanceBefore = address(reps).balance;
        address owner = reps.ownerOf(rep);
        uint256 balanceBefore = owner.balance;

        // fast forward
        vm.warp(block.timestamp + time2);
        uint256 claimable = reps.claimableAt(rep, block.timestamp);

        // claim
        vm.expectEmit(false, false, false, true);
        emit TransferETH(owner, claimable, true);
        reps.claimFor(rep);
        assertEq(
            repsBalanceBefore - claimable,
            address(reps).balance,
            "reps balance"
        );
        assertEq(balanceBefore + claimable, owner.balance, "owner balance");
    }

    function testClaimFor_WETH(
        uint64 payment,
        uint64 time1,
        uint64 time2
    ) public {
        // set up rep with payment
        uint256 rep = testBoostEthFor(payment, time1);
        uint256 repsBalanceBefore = address(reps).balance;
        uint256 vmWethBefore = weth.balanceOf(address(vm));
        uint256 vmBalanceBefore = address(vm).balance;

        // fast forward
        vm.warp(block.timestamp + time2);
        uint256 claimable = reps.claimableAt(rep, block.timestamp);

        // transfer Rep NFT to new owner that can't receive ETH
        vm.prank(alice);
        vm.expectEmit(true, true, true, false);
        emit Transfer(alice, address(vm), rep);
        reps.transferFrom(alice, address(vm), rep);

        // claim for new owner, who should receive WETH instead of ETH
        vm.expectEmit(false, false, false, true);
        emit TransferETH(address(vm), claimable, false);
        reps.claimFor(rep);

        assertEq(
            repsBalanceBefore - claimable,
            address(reps).balance,
            "reps balance"
        );
        assertEq(vmBalanceBefore, address(vm).balance, "new owner ETH balance");
        assertEq(
            vmWethBefore + claimable,
            weth.balanceOf(address(vm)),
            "new owner WETH balance"
        );
    }

    function testFailClaimFor_NonexistentRep() public {
        reps.claimFor(1);
    }

    //===== dispute =====//

    function testDispute() public returns (uint256 dispute) {
        uint256 rep = testNewRep(alice);
        uint256 fee = arb.arbitrationCost("");
        vm.expectEmit(true, true, false, false);
        emit DisputeCreation(0, reps);
        dispute = reps.dispute{value: fee}(rep);
        checkDisputeData(rep, 0, address(this));
    }

    function testFailDispute_AlreadyDisputed() public {
        uint256 rep = testNewRep(alice);
        uint256 fee = arb.arbitrationCost("");
        vm.expectEmit(true, true, false, false);
        emit DisputeCreation(0, reps);
        reps.dispute{value: fee}(rep);
        checkDisputeData(rep, 0, address(this));
        reps.dispute{value: fee}(rep);
    }

    function testFailDispute_InvalidValue() public {
        uint256 rep = testNewRep(alice);
        uint256 fee = arb.arbitrationCost("");
        uint256 dispute = reps.dispute{value: fee - 1}(rep);
    }

    //===== rule =====//

    function testRule_Ruling0(uint64 payment) public {
        // set up and pay Rep
        (uint256 rep, bytes32 delegationId) = testSetRep(payment);
        address owner = reps.ownerOf(rep);
        uint256 fee = arb.arbitrationCost("");

        // create dispute
        bob.call{value: 1 ether}("");
        vm.expectEmit(true, true, false, false);
        emit DisputeCreation(0, reps);
        vm.prank(bob);
        uint256 dispute = reps.dispute{value: fee}(rep);
        checkDisputeData(rep, dispute, bob);

        // rule dispute
        uint256 bobBalance = bob.balance;
        uint256 ruling = 0;
        vm.expectEmit(true, true, false, true);
        emit Ruling(arb, dispute, ruling);
        vm.prank(address(arb));
        reps.rule(dispute, ruling);

        // ruling 0 consequences: reset dispute, no other change
        assertEq(bobBalance, bob.balance, "bob balance");
        assertEq(reps.ownerOf(rep), owner, "rep owner");
        checkPaymentData(rep, block.timestamp, 0, payment, payment);
        checkDisputeData(rep, 0, address(0));
    }

    function testRule_Ruling1(
        uint64 payment1,
        uint64 payment2,
        uint64 time
    ) public {
        // set up and pay Rep
        (uint256 rep, bytes32 delegationId) = testSetRep(payment1);
        uint256 fee = arb.arbitrationCost("");
        // warp and pay again so claimable[rep] has an interesting value
        vm.warp(block.timestamp + time);
        reps.boostEthFor{value: payment2}(rep);

        // create dispute
        bob.call{value: 1 ether}("");
        vm.expectEmit(true, true, false, false);
        emit DisputeCreation(0, reps);
        vm.prank(bob);
        uint256 dispute = reps.dispute{value: fee}(rep);
        checkDisputeData(rep, dispute, bob);

        // rule dispute
        uint256 bobBalance = bob.balance;
        uint256 ruling = 1;
        vm.expectEmit(true, true, false, true);
        emit Ruling(arb, dispute, ruling);
        vm.prank(address(arb));
        reps.rule(dispute, ruling);

        // ruling 1 consequences: pay bob the rep's pool, burn the NFT
        assertEq(bobBalance + payment1 + payment2, bob.balance, "bob balance");
        assertEq(reps.ownerOf(rep), address(0), "rep owner");
    }

    function testRule_Ruling2(uint64 payment) public {
        // set up and pay Rep
        (uint256 rep, bytes32 delegationId) = testSetRep(payment);
        address owner = reps.ownerOf(rep);
        uint256 fee = arb.arbitrationCost("");

        // create dispute
        bob.call{value: 1 ether}("");
        vm.expectEmit(true, true, false, false);
        emit DisputeCreation(0, reps);
        vm.prank(bob);
        uint256 dispute = reps.dispute{value: fee}(rep);
        checkDisputeData(rep, dispute, bob);

        // rule dispute
        uint256 bobBalance = bob.balance;
        uint256 ruling = 0;
        vm.expectEmit(true, true, false, true);
        emit Ruling(arb, dispute, ruling);
        vm.prank(address(arb));
        reps.rule(dispute, ruling);

        // ruling 2 consequences: reset dispute, no other change
        assertEq(bobBalance, bob.balance, "bob balance");
        assertEq(reps.ownerOf(rep), owner, "rep owner");
        checkPaymentData(rep, block.timestamp, 0, payment, payment);
        checkDisputeData(rep, 0, address(0));
    }

    function testFailRule_NonexistentDispute(uint64 payment) public {
        // set up and pay Rep
        (uint256 rep, bytes32 delegationId) = testSetRep(payment);
        address owner = reps.ownerOf(rep);
        uint256 fee = arb.arbitrationCost("");

        // don't create dispute

        // try to rule nonexistent dispute
        uint256 bobBalance = bob.balance;
        uint256 ruling = 0;
        vm.prank(address(arb));
        reps.rule(1, ruling);
    }

    function testFailRule_WrongCaller(uint64 payment) public {
        // set up and pay Rep
        (uint256 rep, bytes32 delegationId) = testSetRep(payment);
        address owner = reps.ownerOf(rep);
        uint256 fee = arb.arbitrationCost("");

        // create dispute
        bob.call{value: 1 ether}("");
        vm.expectEmit(true, true, false, false);
        emit DisputeCreation(0, reps);
        vm.prank(bob);
        uint256 dispute = reps.dispute{value: fee}(rep);
        checkDisputeData(rep, dispute, bob);

        // rule dispute
        uint256 bobBalance = bob.balance;
        uint256 ruling = 0;
        /* no prank(address(arb)) */
        reps.rule(dispute, ruling);
    }
}
