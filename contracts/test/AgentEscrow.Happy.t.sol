// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {AgentEscrowTestBase} from "./AgentEscrow.Base.t.sol";
import {AgentEscrow} from "../AgentEscrow.sol";

contract AgentEscrowHappyTest is AgentEscrowTestBase {

    // ── createTask ────────────────────────────────────────────────────────────

    function test_CreateTask_TransfersUsdcToEscrow() public {
        uint256 clientBefore = usdc.balanceOf(client);
        _defaultTask();
        assertEq(usdc.balanceOf(client),          clientBefore - AMOUNT);
        assertEq(usdc.balanceOf(address(escrow)), AMOUNT);
    }

    function test_CreateTask_StoresTaskFields() public {
        uint256 taskId = _defaultTask();
        AgentEscrow.Task memory t = escrow.getTask(taskId);

        assertEq(t.client,          client);
        assertEq(t.worker,          worker);
        assertEq(t.amount,          AMOUNT);
        assertEq(t.deadline,        deadline);
        assertEq(t.workerClaimAfter, deadline + 7 days);
        assertEq(uint8(t.state),    uint8(AgentEscrow.TaskState.Created));
        assertEq(t.resultHash,      bytes32(0));
    }

    function test_CreateTask_EmitsTaskCreated() public {
        uint256 expectedId          = escrow.taskCount() + 1;
        uint256 expectedClaimAfter  = deadline + 7 days;

        vm.prank(client);
        vm.expectEmit(true, true, true, true, address(escrow));
        emit AgentEscrow.TaskCreated(expectedId, client, worker, AMOUNT, deadline, expectedClaimAfter);
        escrow.createTask(worker, AMOUNT, deadline);
    }

    function test_CreateTask_ReturnsCorrectTaskId() public {
        uint256 id1 = _defaultTask();
        uint256 id2 = _defaultTask();
        assertEq(id1, 1);
        assertEq(id2, 2);
    }

    // ── submitResult ──────────────────────────────────────────────────────────

    function test_SubmitResult_SetsStateToSubmitted() public {
        uint256 taskId = _defaultTask();
        _submitResult(taskId);
        AgentEscrow.Task memory t = escrow.getTask(taskId);
        assertEq(uint8(t.state), uint8(AgentEscrow.TaskState.Submitted));
    }

    function test_SubmitResult_StoresResultHash() public {
        uint256 taskId  = _defaultTask();
        bytes32 hash    = keccak256("my-result");
        vm.prank(worker);
        escrow.submitResult(taskId, hash);
        assertEq(escrow.getTask(taskId).resultHash, hash);
    }

    function test_SubmitResult_EmitsResultSubmitted() public {
        uint256 taskId = _defaultTask();
        bytes32 hash   = keccak256("my-result");

        vm.prank(worker);
        vm.expectEmit(true, true, false, true, address(escrow));
        emit AgentEscrow.ResultSubmitted(taskId, worker, hash);
        escrow.submitResult(taskId, hash);
    }

    // ── approveRelease ────────────────────────────────────────────────────────

    function test_ApproveRelease_SetsStateToReleased() public {
        uint256 taskId = _taskSubmitted();
        vm.prank(client);
        escrow.approveRelease(taskId);
        assertEq(uint8(escrow.getTask(taskId).state), uint8(AgentEscrow.TaskState.Released));
    }

    function test_ApproveRelease_AddsToPendingWithdrawals() public {
        uint256 taskId = _taskSubmitted();
        vm.prank(client);
        escrow.approveRelease(taskId);
        // worker pending balance must equal AMOUNT; verified via withdraw behaviour below
        // (pendingWithdrawals is private — we verify through the withdraw flow)
        vm.prank(worker);
        escrow.withdraw();
        assertEq(usdc.balanceOf(worker), AMOUNT);
    }

    function test_ApproveRelease_EmitsPaymentReleased() public {
        uint256 taskId = _taskSubmitted();

        vm.prank(client);
        vm.expectEmit(true, true, false, true, address(escrow));
        emit AgentEscrow.PaymentReleased(taskId, worker, AMOUNT);
        escrow.approveRelease(taskId);
    }

    // ── reclaim ───────────────────────────────────────────────────────────────

    function test_Reclaim_SetsStateToReclaimed() public {
        uint256 taskId = _defaultTask();
        vm.warp(deadline + 1);
        vm.prank(client);
        escrow.reclaim(taskId);
        assertEq(uint8(escrow.getTask(taskId).state), uint8(AgentEscrow.TaskState.Reclaimed));
    }

    function test_Reclaim_TransfersUsdcBackToClient() public {
        uint256 taskId      = _defaultTask();
        uint256 clientAfterCreate = usdc.balanceOf(client);

        vm.warp(deadline + 1);
        vm.prank(client);
        escrow.reclaim(taskId);

        assertEq(usdc.balanceOf(client),          clientAfterCreate + AMOUNT);
        assertEq(usdc.balanceOf(address(escrow)), 0);
    }

    function test_Reclaim_EmitsPaymentReclaimed() public {
        uint256 taskId = _defaultTask();
        vm.warp(deadline + 1);

        vm.prank(client);
        vm.expectEmit(true, true, false, true, address(escrow));
        emit AgentEscrow.PaymentReclaimed(taskId, client, AMOUNT);
        escrow.reclaim(taskId);
    }

    // ── workerClaim ───────────────────────────────────────────────────────────

    function test_WorkerClaim_SetsStateToReleased() public {
        uint256 taskId = _taskSubmitted();
        vm.warp(deadline + 7 days);
        vm.prank(worker);
        escrow.workerClaim(taskId);
        assertEq(uint8(escrow.getTask(taskId).state), uint8(AgentEscrow.TaskState.Released));
    }

    function test_WorkerClaim_AddsToPendingWithdrawals() public {
        uint256 taskId = _taskSubmitted();
        vm.warp(deadline + 7 days);
        vm.prank(worker);
        escrow.workerClaim(taskId);

        // Drain via withdraw to confirm amount
        vm.prank(worker);
        escrow.withdraw();
        assertEq(usdc.balanceOf(worker), AMOUNT);
    }

    function test_WorkerClaim_EmitsPaymentReleased() public {
        uint256 taskId = _taskSubmitted();
        vm.warp(deadline + 7 days);

        vm.prank(worker);
        vm.expectEmit(true, true, false, true, address(escrow));
        emit AgentEscrow.PaymentReleased(taskId, worker, AMOUNT);
        escrow.workerClaim(taskId);
    }

    // ── withdraw ──────────────────────────────────────────────────────────────

    function test_Withdraw_TransfersFullPendingBalance() public {
        uint256 taskId = _taskReleased();
        (taskId);                              // silence unused var warning

        uint256 workerBefore = usdc.balanceOf(worker);
        vm.prank(worker);
        escrow.withdraw();
        assertEq(usdc.balanceOf(worker), workerBefore + AMOUNT);
    }

    function test_Withdraw_ZeroesPendingBalance() public {
        _taskReleased();
        vm.prank(worker);
        escrow.withdraw();

        // Second call must revert — pending is now 0.
        vm.prank(worker);
        vm.expectRevert(AgentEscrow.NoPendingWithdrawal.selector);
        escrow.withdraw();
    }

    function test_Withdraw_EmitsWithdrawn() public {
        _taskReleased();

        vm.prank(worker);
        vm.expectEmit(true, false, false, true, address(escrow));
        emit AgentEscrow.Withdrawn(worker, AMOUNT);
        escrow.withdraw();
    }

    function test_Withdraw_AccumulatesMultipleTasks() public {
        // Create and release two tasks; worker should get 2×AMOUNT in one withdraw.
        uint256 id1 = _taskSubmitted();
        uint256 id2 = _taskSubmitted();

        vm.prank(client);
        escrow.approveRelease(id1);
        vm.prank(client);
        escrow.approveRelease(id2);

        vm.prank(worker);
        escrow.withdraw();
        assertEq(usdc.balanceOf(worker), 2 * AMOUNT);
    }
}
