// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {AgentEscrowTestBase} from "./AgentEscrow.Base.t.sol";
import {AgentEscrow} from "../AgentEscrow.sol";

contract AgentEscrowFuzzTest is AgentEscrowTestBase {

    /// @dev workerClaimAfter must always equal deadline + 7 days exactly.
    function testFuzz_CreateTask_WorkerClaimAfterIsDeadlinePlusSevenDays(
        uint256 amount,
        uint256 deadlineOffset
    ) public {
        amount         = bound(amount,         1,        50_000e6);
        deadlineOffset = bound(deadlineOffset, 1,        365 days);

        uint256 dl = block.timestamp + deadlineOffset;

        usdc.mint(client, amount);
        // client already has max approval from setUp

        vm.prank(client);
        uint256 taskId = escrow.createTask(worker, amount, dl);

        AgentEscrow.Task memory t = escrow.getTask(taskId);
        assertEq(t.workerClaimAfter, dl + 7 days);
    }

    /// @dev Escrowed amount must equal stored task.amount for any valid input.
    function testFuzz_CreateTask_EscrowedAmountMatchesTaskAmount(uint256 amount) public {
        amount = bound(amount, 1, 50_000e6);

        usdc.mint(client, amount);

        uint256 escrowBefore = usdc.balanceOf(address(escrow));

        vm.prank(client);
        uint256 taskId = escrow.createTask(worker, amount, block.timestamp + 1 days);

        assertEq(usdc.balanceOf(address(escrow)), escrowBefore + amount);
        assertEq(escrow.getTask(taskId).amount,   amount);
    }

    /// @dev Client's USDC decreases by exactly the escrowed amount.
    function testFuzz_CreateTask_ClientBalanceDecreasesByAmount(uint256 amount) public {
        amount = bound(amount, 1, 50_000e6);

        usdc.mint(client, amount);
        uint256 clientBefore = usdc.balanceOf(client);

        vm.prank(client);
        escrow.createTask(worker, amount, block.timestamp + 1 days);

        assertEq(usdc.balanceOf(client), clientBefore - amount);
    }

    /// @dev After approveRelease + withdraw, worker receives exactly task.amount.
    function testFuzz_ApproveRelease_WorkerReceivesExactAmount(uint256 amount) public {
        amount = bound(amount, 1, 50_000e6);

        usdc.mint(client, amount);

        vm.prank(client);
        uint256 taskId = escrow.createTask(worker, amount, block.timestamp + 1 days);

        vm.prank(worker);
        escrow.submitResult(taskId, keccak256("r"));

        vm.prank(client);
        escrow.approveRelease(taskId);

        uint256 workerBefore = usdc.balanceOf(worker);
        vm.prank(worker);
        escrow.withdraw();

        assertEq(usdc.balanceOf(worker), workerBefore + amount);
    }

    /// @dev After workerClaim + withdraw, worker receives exactly task.amount.
    function testFuzz_WorkerClaim_WorkerReceivesExactAmount(uint256 amount) public {
        amount = bound(amount, 1, 50_000e6);

        usdc.mint(client, amount);

        vm.prank(client);
        uint256 taskId = escrow.createTask(worker, amount, block.timestamp + 1 days);

        vm.prank(worker);
        escrow.submitResult(taskId, keccak256("r"));

        // advance past workerClaimAfter
        vm.warp(block.timestamp + 1 days + 7 days);

        vm.prank(worker);
        escrow.workerClaim(taskId);

        uint256 workerBefore = usdc.balanceOf(worker);
        vm.prank(worker);
        escrow.withdraw();

        assertEq(usdc.balanceOf(worker), workerBefore + amount);
    }

    /// @dev After reclaim, client gets back exactly task.amount.
    function testFuzz_Reclaim_ClientReceivesExactAmount(uint256 amount) public {
        amount = bound(amount, 1, 50_000e6);

        usdc.mint(client, amount);
        uint256 clientBefore = usdc.balanceOf(client);

        vm.prank(client);
        uint256 dl     = block.timestamp + 1 days;
        uint256 taskId = escrow.createTask(worker, amount, dl);
        (taskId);

        vm.warp(dl + 1);
        vm.prank(client);
        escrow.reclaim(taskId);

        assertEq(usdc.balanceOf(client), clientBefore);  // net zero change
    }

    /// @dev Deadline must be strictly in the future; boundary at block.timestamp must revert.
    function testFuzz_CreateTask_RevertWhenDeadlineNotInFuture(uint256 deadlineOffset) public {
        // deadlineOffset == 0 → deadline == block.timestamp (invalid)
        deadlineOffset = bound(deadlineOffset, 0, 0);   // force exactly 0
        vm.prank(client);
        vm.expectRevert(AgentEscrow.InvalidDeadline.selector);
        escrow.createTask(worker, AMOUNT, block.timestamp + deadlineOffset);
    }

    /// @dev Multiple released tasks accumulate correctly in pendingWithdrawals.
    function testFuzz_PendingWithdrawals_AccumulateAcrossMultipleTasks(
        uint256 amount1,
        uint256 amount2
    ) public {
        amount1 = bound(amount1, 1, 25_000e6);
        amount2 = bound(amount2, 1, 25_000e6);

        usdc.mint(client, amount1 + amount2);

        uint256 dl = block.timestamp + 1 days;

        vm.prank(client);
        uint256 id1 = escrow.createTask(worker, amount1, dl);
        vm.prank(client);
        uint256 id2 = escrow.createTask(worker, amount2, dl);

        vm.prank(worker); escrow.submitResult(id1, keccak256("r1"));
        vm.prank(worker); escrow.submitResult(id2, keccak256("r2"));

        vm.prank(client); escrow.approveRelease(id1);
        vm.prank(client); escrow.approveRelease(id2);

        uint256 workerBefore = usdc.balanceOf(worker);
        vm.prank(worker);
        escrow.withdraw();

        assertEq(usdc.balanceOf(worker), workerBefore + amount1 + amount2);
    }
}
