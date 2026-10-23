// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {AgentEscrowTestBase} from "./AgentEscrow.Base.t.sol";
import {AgentEscrow} from "../AgentEscrow.sol";

contract AgentEscrowRevertTest is AgentEscrowTestBase {

    // ── createTask ────────────────────────────────────────────────────────────

    function test_CreateTask_RevertZeroWorker() public {
        vm.prank(client);
        vm.expectRevert(AgentEscrow.ZeroAddress.selector);
        escrow.createTask(address(0), AMOUNT, deadline);
    }

    function test_CreateTask_RevertZeroAmount() public {
        vm.prank(client);
        vm.expectRevert(AgentEscrow.InvalidAmount.selector);
        escrow.createTask(worker, 0, deadline);
    }

    function test_CreateTask_RevertDeadlineInPast() public {
        vm.prank(client);
        vm.expectRevert(AgentEscrow.InvalidDeadline.selector);
        escrow.createTask(worker, AMOUNT, block.timestamp); // equal == invalid
    }

    function test_CreateTask_RevertDeadlineStrictlyInPast() public {
        vm.prank(client);
        vm.expectRevert(AgentEscrow.InvalidDeadline.selector);
        escrow.createTask(worker, AMOUNT, block.timestamp - 1);
    }

    function test_CreateTask_RevertInsufficientAllowance() public {
        address richUser = makeAddr("richUser");
        usdc.mint(richUser, AMOUNT);
        // richUser never approved the escrow
        vm.prank(richUser);
        vm.expectRevert();   // SafeERC20 wraps ERC-20 revert
        escrow.createTask(worker, AMOUNT, deadline);
    }

    function test_CreateTask_RevertInsufficientBalance() public {
        address poorUser = makeAddr("poorUser");
        // poorUser has 0 USDC but has approved the escrow
        vm.prank(poorUser);
        usdc.approve(address(escrow), type(uint256).max);
        vm.prank(poorUser);
        vm.expectRevert();   // SafeERC20 wraps ERC-20 revert
        escrow.createTask(worker, AMOUNT, deadline);
    }

    // ── submitResult ──────────────────────────────────────────────────────────

    function test_SubmitResult_RevertNonWorker() public {
        uint256 taskId = _defaultTask();
        vm.prank(stranger);
        vm.expectRevert(AgentEscrow.UnauthorizedWorker.selector);
        escrow.submitResult(taskId, keccak256("x"));
    }

    function test_SubmitResult_RevertClientCannotSubmit() public {
        uint256 taskId = _defaultTask();
        vm.prank(client);
        vm.expectRevert(AgentEscrow.UnauthorizedWorker.selector);
        escrow.submitResult(taskId, keccak256("x"));
    }

    function test_SubmitResult_RevertAfterDeadline() public {
        uint256 taskId = _defaultTask();
        vm.warp(deadline + 1);
        vm.prank(worker);
        vm.expectRevert(AgentEscrow.DeadlinePassed.selector);
        escrow.submitResult(taskId, keccak256("x"));
    }

    function test_SubmitResult_RevertAlreadySubmitted() public {
        uint256 taskId = _taskSubmitted();
        vm.prank(worker);
        vm.expectRevert(AgentEscrow.InvalidState.selector);
        escrow.submitResult(taskId, keccak256("second"));
    }

    function test_SubmitResult_RevertOnReleasedTask() public {
        uint256 taskId = _taskReleased();
        vm.prank(worker);
        vm.expectRevert(AgentEscrow.InvalidState.selector);
        escrow.submitResult(taskId, keccak256("late"));
    }

    function test_SubmitResult_RevertInvalidTaskId() public {
        vm.prank(worker);
        vm.expectRevert(AgentEscrow.InvalidState.selector);
        escrow.submitResult(9999, keccak256("x"));
    }

    // ── approveRelease ────────────────────────────────────────────────────────

    function test_ApproveRelease_RevertNonClient() public {
        uint256 taskId = _taskSubmitted();
        vm.prank(stranger);
        vm.expectRevert(AgentEscrow.UnauthorizedClient.selector);
        escrow.approveRelease(taskId);
    }

    function test_ApproveRelease_RevertWorkerCannotApprove() public {
        uint256 taskId = _taskSubmitted();
        vm.prank(worker);
        vm.expectRevert(AgentEscrow.UnauthorizedClient.selector);
        escrow.approveRelease(taskId);
    }

    function test_ApproveRelease_RevertOnCreatedState() public {
        uint256 taskId = _defaultTask();   // still Created, not Submitted
        vm.prank(client);
        vm.expectRevert(AgentEscrow.InvalidState.selector);
        escrow.approveRelease(taskId);
    }

    function test_ApproveRelease_RevertDoubleApprove() public {
        uint256 taskId = _taskSubmitted();
        vm.prank(client);
        escrow.approveRelease(taskId);
        vm.prank(client);
        vm.expectRevert(AgentEscrow.InvalidState.selector);
        escrow.approveRelease(taskId);
    }

    function test_ApproveRelease_RevertInvalidTaskId() public {
        vm.prank(client);
        vm.expectRevert(AgentEscrow.InvalidState.selector);
        escrow.approveRelease(9999);
    }

    // ── reclaim ───────────────────────────────────────────────────────────────

    function test_Reclaim_RevertNonClient() public {
        uint256 taskId = _defaultTask();
        vm.warp(deadline + 1);
        vm.prank(stranger);
        vm.expectRevert(AgentEscrow.UnauthorizedClient.selector);
        escrow.reclaim(taskId);
    }

    function test_Reclaim_RevertBeforeDeadline() public {
        uint256 taskId = _defaultTask();
        // Still before deadline
        vm.prank(client);
        vm.expectRevert(AgentEscrow.DeadlineNotReached.selector);
        escrow.reclaim(taskId);
    }

    function test_Reclaim_RevertAtExactDeadline() public {
        uint256 taskId = _defaultTask();
        vm.warp(deadline); // exactly at deadline — still not reached
        vm.prank(client);
        vm.expectRevert(AgentEscrow.DeadlineNotReached.selector);
        escrow.reclaim(taskId);
    }

    function test_Reclaim_RevertOnSubmittedState() public {
        uint256 taskId = _taskSubmitted();
        vm.warp(deadline + 1);
        vm.prank(client);
        vm.expectRevert(AgentEscrow.InvalidState.selector);
        escrow.reclaim(taskId);
    }

    function test_Reclaim_RevertOnReleasedState() public {
        uint256 taskId = _taskReleased();
        vm.warp(deadline + 1);
        vm.prank(client);
        vm.expectRevert(AgentEscrow.InvalidState.selector);
        escrow.reclaim(taskId);
    }

    function test_Reclaim_RevertInvalidTaskId() public {
        vm.prank(client);
        vm.expectRevert(AgentEscrow.InvalidState.selector);
        escrow.reclaim(9999);
    }

    // ── workerClaim ───────────────────────────────────────────────────────────

    function test_WorkerClaim_RevertNonWorker() public {
        uint256 taskId = _taskSubmitted();
        vm.warp(deadline + 7 days);
        vm.prank(stranger);
        vm.expectRevert(AgentEscrow.UnauthorizedWorker.selector);
        escrow.workerClaim(taskId);
    }

    function test_WorkerClaim_RevertClientCannotClaim() public {
        uint256 taskId = _taskSubmitted();
        vm.warp(deadline + 7 days);
        vm.prank(client);
        vm.expectRevert(AgentEscrow.UnauthorizedWorker.selector);
        escrow.workerClaim(taskId);
    }

    function test_WorkerClaim_RevertWindowNotOpen_TooEarly() public {
        uint256 taskId = _taskSubmitted();
        // One second before workerClaimAfter
        vm.warp(deadline + 7 days - 1);
        vm.prank(worker);
        vm.expectRevert(AgentEscrow.WorkerClaimWindowNotOpen.selector);
        escrow.workerClaim(taskId);
    }

    function test_WorkerClaim_RevertOnCreatedState() public {
        uint256 taskId = _defaultTask();   // Created, not Submitted
        vm.warp(deadline + 7 days);
        vm.prank(worker);
        vm.expectRevert(AgentEscrow.WorkerClaimWindowNotOpen.selector);
        escrow.workerClaim(taskId);
    }

    function test_WorkerClaim_RevertOnAlreadyReleasedState() public {
        uint256 taskId = _taskSubmitted();
        vm.warp(deadline + 7 days);
        vm.prank(worker);
        escrow.workerClaim(taskId);        // first claim succeeds — state becomes Released
        // workerClaim checks state != Submitted inside the WorkerClaimWindowNotOpen guard
        vm.prank(worker);
        vm.expectRevert(AgentEscrow.WorkerClaimWindowNotOpen.selector);
        escrow.workerClaim(taskId);        // second must fail — Released != Submitted
    }

    function test_WorkerClaim_RevertInvalidTaskId() public {
        vm.prank(worker);
        vm.expectRevert(AgentEscrow.InvalidState.selector);
        escrow.workerClaim(9999);
    }

    // ── withdraw ──────────────────────────────────────────────────────────────

    function test_Withdraw_RevertNoPendingBalance() public {
        vm.prank(worker);
        vm.expectRevert(AgentEscrow.NoPendingWithdrawal.selector);
        escrow.withdraw();
    }

    function test_Withdraw_RevertAfterAlreadyWithdrawn() public {
        _taskReleased();
        vm.prank(worker);
        escrow.withdraw();                 // first withdraw — OK
        vm.prank(worker);
        vm.expectRevert(AgentEscrow.NoPendingWithdrawal.selector);
        escrow.withdraw();                 // second — must revert
    }
}
