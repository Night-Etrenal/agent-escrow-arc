// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {AgentEscrow} from "../AgentEscrow.sol";
import {MockERC20} from "../test-helpers/MockERC20.sol";

/// @dev Handler that drives the escrow through arbitrary sequences of
///      valid calls. The invariant file imports only this helper.
contract EscrowHandler is Test {

    AgentEscrow public escrow;
    MockERC20   public usdc;

    address public client  = makeAddr("inv-client");
    address public worker  = makeAddr("inv-worker");

    uint256 public ghost_totalCreated;     // sum of amounts for Created tasks
    uint256 public ghost_totalSubmitted;   // sum of amounts for Submitted tasks
    uint256 public ghost_totalPending;     // sum of amounts added to pendingWithdrawals (not yet withdrawn)
    uint256 public ghost_totalWithdrawn;   // sum of amounts actually withdrawn

    // Tracks task ids and their original amounts for invariant bookkeeping.
    uint256[] public taskIds;
    mapping(uint256 => uint256) public taskAmount;
    mapping(uint256 => uint8)   public taskPhase; // 0=Created 1=Submitted 2=Released 3=Reclaimed

    constructor(AgentEscrow _escrow, MockERC20 _usdc) {
        escrow = _escrow;
        usdc   = _usdc;

        // Pre-approve once.
        vm.prank(client);
        usdc.approve(address(escrow), type(uint256).max);
    }

    // ── actions ──────────────────────────────────────────────────────────────

    function createTask(uint256 amount, uint256 deadlineOffset) external {
        amount         = bound(amount,         1,       10_000e6);
        deadlineOffset = bound(deadlineOffset, 1,       30 days);

        usdc.mint(client, amount);

        uint256 dl = block.timestamp + deadlineOffset;
        vm.prank(client);
        uint256 taskId = escrow.createTask(worker, amount, dl);

        taskIds.push(taskId);
        taskAmount[taskId] = amount;
        taskPhase[taskId]  = 0;
        ghost_totalCreated += amount;
    }

    function submitResult(uint256 idxSeed) external {
        uint256[] memory pending = _tasksInPhase(0);
        if (pending.length == 0) return;
        uint256 taskId = pending[idxSeed % pending.length];

        AgentEscrow.Task memory t = escrow.getTask(taskId);
        if (block.timestamp > t.deadline) return;   // would revert — skip

        vm.prank(worker);
        escrow.submitResult(taskId, keccak256(abi.encodePacked(taskId)));

        ghost_totalCreated  -= taskAmount[taskId];
        ghost_totalSubmitted += taskAmount[taskId];
        taskPhase[taskId] = 1;
    }

    function approveRelease(uint256 idxSeed) external {
        uint256[] memory pending = _tasksInPhase(1);
        if (pending.length == 0) return;
        uint256 taskId = pending[idxSeed % pending.length];

        vm.prank(client);
        escrow.approveRelease(taskId);

        ghost_totalSubmitted -= taskAmount[taskId];
        ghost_totalPending   += taskAmount[taskId];
        taskPhase[taskId] = 2;
    }

    function reclaimTask(uint256 idxSeed) external {
        uint256[] memory pending = _tasksInPhase(0);
        if (pending.length == 0) return;
        uint256 taskId = pending[idxSeed % pending.length];

        AgentEscrow.Task memory t = escrow.getTask(taskId);
        if (block.timestamp <= t.deadline) return;  // would revert — skip

        vm.prank(client);
        escrow.reclaim(taskId);

        ghost_totalCreated -= taskAmount[taskId];
        taskPhase[taskId] = 3;
    }

    function workerClaim(uint256 idxSeed) external {
        uint256[] memory pending = _tasksInPhase(1);
        if (pending.length == 0) return;
        uint256 taskId = pending[idxSeed % pending.length];

        AgentEscrow.Task memory t = escrow.getTask(taskId);
        if (block.timestamp < t.workerClaimAfter) return;  // would revert — skip

        vm.prank(worker);
        escrow.workerClaim(taskId);

        ghost_totalSubmitted -= taskAmount[taskId];
        ghost_totalPending   += taskAmount[taskId];
        taskPhase[taskId] = 2;
    }

    function doWithdraw() external {
        uint256 pending = ghost_totalPending;
        if (pending == 0) return;

        vm.prank(worker);
        try escrow.withdraw() {
            ghost_totalPending  -= pending;
            ghost_totalWithdrawn += pending;
        } catch {
            // Nothing to withdraw yet.
        }
    }

    function warpForward(uint256 secs) external {
        secs = bound(secs, 1, 30 days);
        skip(secs);
    }

    // ── helpers ──────────────────────────────────────────────────────────────

    function _tasksInPhase(uint8 phase) internal view returns (uint256[] memory out) {
        uint256 count;
        for (uint256 i; i < taskIds.length; ++i) {
            if (taskPhase[taskIds[i]] == phase) ++count;
        }
        out = new uint256[](count);
        uint256 j;
        for (uint256 i; i < taskIds.length; ++i) {
            if (taskPhase[taskIds[i]] == phase) out[j++] = taskIds[i];
        }
    }

    function taskCount() external view returns (uint256) { return taskIds.length; }
}

// ── Invariant test contract ───────────────────────────────────────────────────

contract AgentEscrowInvariantTest is StdInvariant, Test {
    MockERC20      internal usdc;
    AgentEscrow    internal escrow;
    EscrowHandler  internal handler;

    function setUp() public {
        vm.warp(1_700_000_000);

        usdc    = new MockERC20("Mock USDC", "mUSDC", 6);
        escrow  = new AgentEscrow(address(usdc));
        handler = new EscrowHandler(escrow, usdc);

        targetContract(address(handler));
    }

    /// @notice The escrow's USDC balance must equal
    ///         (active Created amounts) + (active Submitted amounts) + (undrawn Released amounts).
    function invariant_EscrowBalanceCoversActiveFunds() public view {
        uint256 escrowBal = usdc.balanceOf(address(escrow));
        uint256 expected  =
            handler.ghost_totalCreated()   +
            handler.ghost_totalSubmitted() +
            handler.ghost_totalPending();
        assertEq(escrowBal, expected);
    }

    /// @notice Total USDC minted to the handler's client must equal
    ///         escrow balance + worker's USDC balance + ghost_totalWithdrawn.
    function invariant_TotalMintedConserved() public view {
        // Every unit minted to client ends up in exactly one of:
        //   escrow balance (still locked)
        //   worker balance (already withdrawn)
        //   ghost_totalWithdrawn (already withdrawn — same thing, but separated for clarity)
        // Actually simpler: escrow + worker balance = totalMinted - totalReclaimed
        // We use the ghost accounting for active+pending:
        uint256 escrowBal   = usdc.balanceOf(address(escrow));
        uint256 workerBal   = usdc.balanceOf(handler.worker());

        // All USDC ever sent INTO escrow that hasn't been reclaimed must be
        // either still in the escrow or with the worker.
        uint256 totalLocked  = handler.ghost_totalCreated()   +
                               handler.ghost_totalSubmitted() +
                               handler.ghost_totalPending();
        uint256 totalWithdrawn = handler.ghost_totalWithdrawn();

        assertEq(escrowBal,  totalLocked);
        assertEq(workerBal,  totalWithdrawn);
    }

    /// @notice pendingWithdrawals can never exceed the contract's USDC balance.
    function invariant_PendingWithdrawalsNeverExceedBalance() public view {
        uint256 escrowBal = usdc.balanceOf(address(escrow));
        uint256 pending   = handler.ghost_totalPending();
        assertGe(escrowBal, pending);
    }
}
