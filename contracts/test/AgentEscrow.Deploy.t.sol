// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {AgentEscrowTestBase} from "./AgentEscrow.Base.t.sol";
import {AgentEscrow} from "../AgentEscrow.sol";

contract AgentEscrowDeployTest is AgentEscrowTestBase {
    // ── constructor ──────────────────────────────────────────────────────────

    function test_Constructor_StoresUsdc() public view {
        assertEq(address(escrow.usdc()), address(usdc));
    }

    function test_Constructor_TaskCountStartsAtZero() public view {
        assertEq(escrow.taskCount(), 0);
    }

    function test_Constructor_RevertsOnZeroUsdcAddress() public {
        vm.expectRevert(AgentEscrow.ZeroAddress.selector);
        new AgentEscrow(address(0));
    }

    // ── getTask on nonexistent id ────────────────────────────────────────────

    function test_GetTask_RevertsForNonexistentId() public {
        vm.expectRevert(AgentEscrow.InvalidState.selector);
        escrow.getTask(999);
    }

    // ── taskCount increments ─────────────────────────────────────────────────

    function test_TaskCount_IncrementsAfterCreate() public {
        _defaultTask();
        assertEq(escrow.taskCount(), 1);
        _defaultTask();
        assertEq(escrow.taskCount(), 2);
    }
}
