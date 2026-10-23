import { useState, useMemo } from "react";
import {
  ExternalLink,
  CheckCircle,
  RotateCcw,
  Upload,
  Download,
  Loader2,
  ChevronDown,
  ChevronUp,
} from "lucide-react";
import {
  useAccount,
  useWriteContract,
  useWaitForTransactionReceipt,
  useSwitchChain,
} from "wagmi";
import { toast } from "sonner";
import { buildTxExplorerUrl, buildAddressExplorerUrl } from "@/onchain-facts";
import { Amount, usdcDecimalsFor } from "@/onchain-money";
import {
  AGENT_ESCROW_ABI,
  AGENT_ESCROW_ADDRESS,
  ARC_CHAIN_ID,
  TaskData,
  TaskState,
  TASK_STATE_LABEL,
  TASK_STATE_COLOR,
} from "@/contract";

interface Props {
  taskId: bigint;
  task: TaskData;
  onActionDone: () => void;
}

function formatAddress(addr: string) {
  return `${addr.slice(0, 6)}…${addr.slice(-4)}`;
}

function formatDeadline(ts: bigint) {
  const d = new Date(Number(ts) * 1000);
  return d.toLocaleString(undefined, {
    dateStyle: "medium",
    timeStyle: "short",
  });
}

export function TaskCard({ taskId, task, onActionDone }: Props) {
  const { address, chainId } = useAccount();
  const { switchChain } = useSwitchChain();
  const [resultHash, setResultHash] = useState("");
  const [expanded, setExpanded] = useState(false);

  const wrongChain = chainId !== ARC_CHAIN_ID;
  // eslint-disable-next-line react-hooks/exhaustive-deps
  const now = useMemo(() => BigInt(Math.floor(Date.now() / 1000)), []);
  const isClient = address?.toLowerCase() === task.client.toLowerCase();
  const isWorker = address?.toLowerCase() === task.worker.toLowerCase();

  const formattedAmount = Amount.fromRaw(task.amount, usdcDecimalsFor(ARC_CHAIN_ID)).toFixed(2);
  const stateColors = TASK_STATE_COLOR[task.state];

  const { writeContract, data: txHash, isPending, reset } = useWriteContract();
  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({ hash: txHash });

  function handleChain() {
    if (wrongChain) switchChain({ chainId: ARC_CHAIN_ID });
  }

  function handleSubmitResult() {
    if (wrongChain) return handleChain();
    if (!resultHash || !/^0x[0-9a-fA-F]{64}$/.test(resultHash)) {
      toast.error("Enter a valid 32-byte hex hash (0x + 64 hex chars)");
      return;
    }
    writeContract({
      address: AGENT_ESCROW_ADDRESS,
      abi: AGENT_ESCROW_ABI,
      functionName: "submitResult",
      args: [taskId, resultHash as `0x${string}`],
    });
  }

  function handleApproveRelease() {
    if (wrongChain) return handleChain();
    writeContract({
      address: AGENT_ESCROW_ADDRESS,
      abi: AGENT_ESCROW_ABI,
      functionName: "approveRelease",
      args: [taskId],
    });
  }

  function handleReclaim() {
    if (wrongChain) return handleChain();
    writeContract({
      address: AGENT_ESCROW_ADDRESS,
      abi: AGENT_ESCROW_ABI,
      functionName: "reclaim",
      args: [taskId],
    });
  }

  function handleWorkerClaim() {
    if (wrongChain) return handleChain();
    writeContract({
      address: AGENT_ESCROW_ADDRESS,
      abi: AGENT_ESCROW_ABI,
      functionName: "workerClaim",
      args: [taskId],
    });
  }

  function handleWithdraw() {
    if (wrongChain) return handleChain();
    writeContract({
      address: AGENT_ESCROW_ADDRESS,
      abi: AGENT_ESCROW_ABI,
      functionName: "withdraw",
    });
  }

  if (isSuccess && txHash) {
    toast.success("Transaction confirmed", {
      action: {
        label: "View tx",
        onClick: () =>
          window.open(buildTxExplorerUrl(ARC_CHAIN_ID, txHash), "_blank"),
      },
    });
    reset();
    setResultHash("");
    onActionDone();
  }

  const busy = isPending || isConfirming;

  const canApproveRelease =
    isClient && task.state === TaskState.Submitted;
  const canReclaim =
    isClient && task.state === TaskState.Created && now > task.deadline;
  const canSubmitResult =
    isWorker && task.state === TaskState.Created && now <= task.deadline;
  const canWorkerClaim =
    isWorker && task.state === TaskState.Submitted && now >= task.workerClaimAfter;
  const canWithdraw =
    isWorker && task.state === TaskState.Released;

  return (
    <div
      className="overflow-hidden rounded-2xl transition-shadow hover:shadow-md"
      style={{
        background: "var(--surface-strong)",
        border: "1px solid var(--border)",
      }}
    >
      {/* Header row */}
      <div className="flex items-center justify-between px-4 py-3">
        <div className="flex items-center gap-2.5">
          <span
            className="text-sm font-bold tabular-nums"
            style={{ color: "var(--ink)" }}
          >
            #{taskId.toString()}
          </span>
          <span
            className="rounded-full px-2 py-0.5 text-xs font-semibold"
            style={{ background: stateColors.bg, color: stateColors.text }}
          >
            {TASK_STATE_LABEL[task.state]}
          </span>
        </div>
        <div className="flex items-center gap-3">
          <span
            className="display text-base font-bold tabular-nums"
            style={{ color: "var(--ink)" }}
          >
            {formattedAmount}{" "}
            <span style={{ color: "var(--subtle)", fontSize: "0.75rem" }}>
              USDC
            </span>
          </span>
          <button
            onClick={() => setExpanded((x) => !x)}
            className="flex size-7 items-center justify-center rounded-full transition-colors"
            style={{ background: "var(--surface-muted)" }}
            aria-label={expanded ? "Collapse" : "Expand"}
          >
            {expanded ? (
              <ChevronUp className="size-3.5" style={{ color: "var(--muted)" }} />
            ) : (
              <ChevronDown className="size-3.5" style={{ color: "var(--muted)" }} />
            )}
          </button>
        </div>
      </div>

      {/* Quick info row */}
      <div
        className="flex flex-wrap gap-x-4 gap-y-1 px-4 pb-3"
        style={{ borderTop: "1px solid var(--border)" }}
      >
        <span className="pt-2 text-xs" style={{ color: "var(--subtle)" }}>
          Client{" "}
          <a
            href={buildAddressExplorerUrl(ARC_CHAIN_ID, task.client)}
            target="_blank"
            rel="noreferrer"
            className="mono font-medium hover:underline"
            style={{ color: "var(--ink-2)" }}
          >
            {formatAddress(task.client)}
          </a>
        </span>
        <span className="pt-2 text-xs" style={{ color: "var(--subtle)" }}>
          Worker{" "}
          <a
            href={buildAddressExplorerUrl(ARC_CHAIN_ID, task.worker)}
            target="_blank"
            rel="noreferrer"
            className="mono font-medium hover:underline"
            style={{ color: "var(--ink-2)" }}
          >
            {formatAddress(task.worker)}
          </a>
        </span>
        <span className="pt-2 text-xs" style={{ color: "var(--subtle)" }}>
          Deadline{" "}
          <span className="font-medium" style={{ color: "var(--ink-2)" }}>
            {formatDeadline(task.deadline)}
          </span>
        </span>
      </div>

      {/* Expanded details + actions */}
      {expanded && (
        <div
          className="px-4 pb-4"
          style={{ borderTop: "1px solid var(--border)" }}
        >
          {/* Result hash */}
          {task.resultHash !== "0x" + "0".repeat(64) && (
            <div
              className="mt-3 rounded-xl px-3 py-2"
              style={{ background: "var(--surface-muted)" }}
            >
              <p
                className="mb-0.5 text-xs font-semibold uppercase tracking-wider"
                style={{ color: "var(--muted)" }}
              >
                Result Hash
              </p>
              <p
                className="mono text-xs break-all"
                style={{ color: "var(--ink-2)" }}
              >
                {task.resultHash}
              </p>
            </div>
          )}

          {/* Worker claim info */}
          <div className="mt-3">
            <p className="text-xs" style={{ color: "var(--subtle)" }}>
              Worker self-claim opens{" "}
              <span style={{ color: "var(--ink-2)" }}>
                {formatDeadline(task.workerClaimAfter)}
              </span>
            </p>
          </div>

          {/* Actions */}
          <div className="mt-4 flex flex-wrap gap-2">
            {/* Submit result (worker) */}
            {canSubmitResult && (
              <div className="flex w-full flex-col gap-2">
                <input
                  type="text"
                  value={resultHash}
                  onChange={(e) => setResultHash(e.target.value)}
                  placeholder="0x... result hash (32 bytes)"
                  className="mono w-full rounded-xl border px-3 py-2 text-xs outline-none"
                  style={{
                    borderColor: "var(--border)",
                    background: "var(--surface-muted)",
                    color: "var(--ink)",
                  }}
                />
                <ActionButton
                  icon={<Upload className="size-3.5" />}
                  label="Submit Result"
                  busy={busy}
                  onClick={handleSubmitResult}
                  variant="primary"
                />
              </div>
            )}

            {/* Approve release (client) */}
            {canApproveRelease && (
              <ActionButton
                icon={<CheckCircle className="size-3.5" />}
                label="Approve Release"
                busy={busy}
                onClick={handleApproveRelease}
                variant="success"
              />
            )}

            {/* Reclaim (client, after deadline, Created state) */}
            {canReclaim && (
              <ActionButton
                icon={<RotateCcw className="size-3.5" />}
                label="Reclaim USDC"
                busy={busy}
                onClick={handleReclaim}
                variant="muted"
              />
            )}

            {/* Worker self-claim */}
            {canWorkerClaim && (
              <ActionButton
                icon={<Download className="size-3.5" />}
                label="Claim Payment"
                busy={busy}
                onClick={handleWorkerClaim}
                variant="primary"
              />
            )}

            {/* Withdraw (worker, after release) */}
            {canWithdraw && (
              <ActionButton
                icon={<Download className="size-3.5" />}
                label="Withdraw USDC"
                busy={busy}
                onClick={handleWithdraw}
                variant="success"
              />
            )}
          </div>

          {/* Explorer link */}
          <a
            href={`https://explorer.arc.io/address/${AGENT_ESCROW_ADDRESS}`}
            target="_blank"
            rel="noreferrer"
            className="mt-3 inline-flex items-center gap-1 text-xs"
            style={{ color: "var(--muted)" }}
          >
            View contract on ArcScan
            <ExternalLink className="size-3" />
          </a>
        </div>
      )}
    </div>
  );
}

interface ActionButtonProps {
  icon: React.ReactNode;
  label: string;
  busy: boolean;
  onClick: () => void;
  variant: "primary" | "success" | "muted";
}

function ActionButton({ icon, label, busy, onClick, variant }: ActionButtonProps) {
  const styles: Record<typeof variant, React.CSSProperties> = {
    primary: { background: "var(--accent)", color: "white" },
    success: { background: "rgba(26,128,71,0.12)", color: "var(--success)" },
    muted: { background: "var(--surface-muted)", color: "var(--muted)", border: "1px solid var(--border)" },
  };

  return (
    <button
      onClick={onClick}
      disabled={busy}
      className="flex items-center gap-1.5 rounded-xl px-3.5 py-2 text-xs font-semibold transition-all hover:scale-[1.02] active:scale-[0.99] disabled:cursor-not-allowed disabled:opacity-40"
      style={styles[variant]}
    >
      {busy ? <Loader2 className="size-3.5 animate-spin" /> : icon}
      {label}
    </button>
  );
}
