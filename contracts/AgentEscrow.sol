// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract AgentEscrow is ReentrancyGuard {
    using SafeERC20 for IERC20;

    error UnauthorizedWorker();
    error UnauthorizedClient();
    error InvalidDeadline();
    error InvalidAmount();
    error InvalidState();
    error DeadlinePassed();
    error DeadlineNotReached();
    error WorkerClaimWindowNotOpen();
    error NoPendingWithdrawal();
    error ZeroAddress();

    enum TaskState {
        Created,
        Submitted,
        Released,
        Reclaimed
    }

    struct Task {
        address client;
        address worker;
        uint256 amount;
        uint256 deadline;
        uint256 workerClaimAfter;
        bytes32 resultHash;
        TaskState state;
    }

    IERC20 public immutable usdc;

    uint256 private _taskCount;
    mapping(uint256 => Task) private _tasks;
    mapping(address => uint256) private pendingWithdrawals;

    event TaskCreated(
        uint256 indexed taskId,
        address indexed client,
        address indexed worker,
        uint256 amount,
        uint256 deadline,
        uint256 workerClaimAfter
    );

    event ResultSubmitted(uint256 indexed taskId, address indexed worker, bytes32 resultHash);

    event PaymentReleased(uint256 indexed taskId, address indexed worker, uint256 amount);

    event PaymentReclaimed(uint256 indexed taskId, address indexed client, uint256 amount);

    event Withdrawn(address indexed recipient, uint256 amount);

    /// @notice Creates the escrow contract for a specific USDC token.
    /// @param usdc_ The ERC-20 token address used for escrowed payments.
    constructor(address usdc_) {
        if (usdc_ == address(0)) revert ZeroAddress();
        usdc = IERC20(usdc_);
    }

    /// @notice Creates a new task and escrows USDC from the caller.
    /// @param worker The worker assigned to complete the task.
    /// @param amount The USDC amount to escrow for the task.
    /// @param deadline The unix timestamp after which unreleased funds may be reclaimed.
    /// @return taskId The newly created task identifier.
    function createTask(address worker, uint256 amount, uint256 deadline) external nonReentrant returns (uint256 taskId) {
        if (worker == address(0)) revert ZeroAddress();
        if (amount == 0) revert InvalidAmount();
        if (deadline <= block.timestamp) revert InvalidDeadline();

        taskId = ++_taskCount;
        uint256 workerClaimAfter = deadline + 7 days;

        _tasks[taskId] = Task({
            client: msg.sender,
            worker: worker,
            amount: amount,
            deadline: deadline,
            workerClaimAfter: workerClaimAfter,
            resultHash: bytes32(0),
            state: TaskState.Created
        });

        usdc.safeTransferFrom(msg.sender, address(this), amount);

        emit TaskCreated(taskId, msg.sender, worker, amount, deadline, workerClaimAfter);
    }

    /// @notice Records the worker's task result hash before the task deadline.
    /// @param taskId The task identifier.
    /// @param resultHash The hash of the worker's result payload.
    function submitResult(uint256 taskId, bytes32 resultHash) external nonReentrant {
        Task storage task = _getTaskOrRevert(taskId);

        if (msg.sender != task.worker) revert UnauthorizedWorker();
        if (task.state != TaskState.Created) revert InvalidState();
        if (block.timestamp > task.deadline) revert DeadlinePassed();

        task.resultHash = resultHash;
        task.state = TaskState.Submitted;

        emit ResultSubmitted(taskId, msg.sender, resultHash);
    }

    /// @notice Queues escrowed USDC for worker withdrawal after client approval.
    /// @param taskId The task identifier.
    function approveRelease(uint256 taskId) external nonReentrant {
        Task storage task = _getTaskOrRevert(taskId);

        if (msg.sender != task.client) revert UnauthorizedClient();
        if (task.state != TaskState.Submitted) revert InvalidState();

        task.state = TaskState.Released;
        pendingWithdrawals[task.worker] += task.amount;

        emit PaymentReleased(taskId, task.worker, task.amount);
    }

    /// @notice Allows the assigned worker to self-claim payment after the worker claim window opens.
    /// @param taskId The task identifier.
    function workerClaim(uint256 taskId) external nonReentrant {
        Task storage task = _getTaskOrRevert(taskId);

        if (msg.sender != task.worker) revert UnauthorizedWorker();
        if (task.state != TaskState.Submitted || block.timestamp < task.workerClaimAfter) {
            revert WorkerClaimWindowNotOpen();
        }

        task.state = TaskState.Released;
        pendingWithdrawals[task.worker] += task.amount;

        emit PaymentReleased(taskId, task.worker, task.amount);
    }

    /// @notice Withdraws caller's queued USDC payments.
    function withdraw() external nonReentrant {
        uint256 amount = pendingWithdrawals[msg.sender];
        if (amount == 0) revert NoPendingWithdrawal();

        pendingWithdrawals[msg.sender] = 0;
        usdc.safeTransfer(msg.sender, amount);

        emit Withdrawn(msg.sender, amount);
    }

    /// @notice Reclaims escrowed USDC after deadline when no result was submitted.
    /// @param taskId The task identifier.
    function reclaim(uint256 taskId) external nonReentrant {
        Task storage task = _getTaskOrRevert(taskId);

        if (msg.sender != task.client) revert UnauthorizedClient();
        if (block.timestamp <= task.deadline) revert DeadlineNotReached();
        if (task.state != TaskState.Created) revert InvalidState();

        task.state = TaskState.Reclaimed;
        usdc.safeTransfer(task.client, task.amount);

        emit PaymentReclaimed(taskId, task.client, task.amount);
    }

    /// @notice Returns task details for a given task identifier.
    /// @param taskId The task identifier.
    /// @return task The full task record.
    function getTask(uint256 taskId) external view returns (Task memory task) {
        task = _tasks[taskId];
        if (task.client == address(0)) revert InvalidState();
    }

    /// @notice Returns the number of tasks created so far.
    /// @return count The latest task counter value.
    function taskCount() external view returns (uint256 count) {
        count = _taskCount;
    }

    function _getTaskOrRevert(uint256 taskId) internal view returns (Task storage task) {
        task = _tasks[taskId];
        if (task.client == address(0)) revert InvalidState();
    }
}
