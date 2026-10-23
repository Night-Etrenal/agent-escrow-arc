// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {AgentEscrow} from "../AgentEscrow.sol";
import {MockERC20} from "../test-helpers/MockERC20.sol";

/// @dev Shared state, actors, and helpers for all AgentEscrow test suites.
abstract contract AgentEscrowTestBase is Test {
    // ── actors ──────────────────────────────────────────────────────────────
    address internal client  = makeAddr("client");
    address internal worker  = makeAddr("worker");
    address internal stranger = makeAddr("stranger");

    // ── constants ───────────────────────────────────────────────────────────
    uint256 internal constant AMOUNT    = 1_000e6;   // 1 000 USDC (6 dec)
    uint256 internal constant DEADLINE_OFFSET = 1 days; // relative to block.timestamp in setUp

    // ── contracts ───────────────────────────────────────────────────────────
    MockERC20   internal usdc;
    AgentEscrow internal escrow;

    // ── deadline cached at setUp time ────────────────────────────────────────
    uint256 internal deadline;

    function setUp() public virtual {
        // Start at a predictable timestamp so relative offsets are stable.
        vm.warp(1_700_000_000);

        usdc   = new MockERC20("Mock USDC", "mUSDC", 6);
        escrow = new AgentEscrow(address(usdc));

        deadline = block.timestamp + DEADLINE_OFFSET;

        // Fund client with USDC and pre-approve the escrow.
        usdc.mint(client, 100_000e6);
        vm.prank(client);
        usdc.approve(address(escrow), type(uint256).max);
    }

    // ── helpers ──────────────────────────────────────────────────────────────

    /// Create a task from `client` and return its taskId.
    function _createTask(uint256 amount, uint256 dl) internal returns (uint256 taskId) {
        vm.prank(client);
        taskId = escrow.createTask(worker, amount, dl);
    }

    /// Create a default task (AMOUNT, deadline) and return its taskId.
    function _defaultTask() internal returns (uint256 taskId) {
        taskId = _createTask(AMOUNT, deadline);
    }

    /// Create a task and submit a result from the worker.
    function _submitResult(uint256 taskId) internal {
        vm.prank(worker);
        escrow.submitResult(taskId, keccak256("result"));
    }

    /// Full happy path up to Submitted state.
    function _taskSubmitted() internal returns (uint256 taskId) {
        taskId = _defaultTask();
        _submitResult(taskId);
    }

    /// Full happy path up to Released state (client approved).
    function _taskReleased() internal returns (uint256 taskId) {
        taskId = _taskSubmitted();
        vm.prank(client);
        escrow.approveRelease(taskId);
    }
}
