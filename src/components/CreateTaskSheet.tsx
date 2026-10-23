import { useState } from "react";
import { AnimatePresence, motion } from "framer-motion";
import { X, Loader2 } from "lucide-react";
import {
  useAccount,
  useWriteContract,
  useWaitForTransactionReceipt,
  useSwitchChain,
  useReadContract,
} from "wagmi";
import { erc20Abi } from "viem";
import { toast } from "sonner";
import { getUsdc, buildTxExplorerUrl } from "@/onchain-facts";
import { parseAmount, Amount, usdcDecimalsFor } from "@/onchain-money";
import {
  AGENT_ESCROW_ADDRESS,
  AGENT_ESCROW_ABI,
  ARC_CHAIN_ID,
} from "@/contract";

interface Props {
  open: boolean;
  onClose: () => void;
  onCreated: () => void;
}

const springs = {
  sheet: { type: "spring" as const, damping: 30, stiffness: 320 },
};

export function CreateTaskSheet({ open, onClose, onCreated }: Props) {
  const { address, chainId } = useAccount();
  const { switchChain } = useSwitchChain();

  const [worker, setWorker] = useState("");
  const [amount, setAmount] = useState("");
  const [deadlineDays, setDeadlineDays] = useState("7");

  const wrongChain = chainId !== ARC_CHAIN_ID;
  const usdcFact = getUsdc(ARC_CHAIN_ID);
  const usdcAddress = usdcFact?.address as `0x${string}` | undefined;

  const { data: usdcBalance } = useReadContract({
    address: usdcAddress,
    abi: erc20Abi,
    functionName: "balanceOf",
    args: address ? [address] : undefined,
    chainId: ARC_CHAIN_ID,
    query: { enabled: !!address && !!usdcAddress },
  });

  const formattedBalance = usdcBalance != null
    ? Amount.fromRaw(usdcBalance, usdcDecimalsFor(ARC_CHAIN_ID)).toFixed(2)
    : null;

  // Step 1: Approve USDC
  const {
    writeContract: approve,
    data: approveHash,
    isPending: approveIsPending,
    reset: resetApprove,
  } = useWriteContract();
  const { isLoading: approveConfirming, isSuccess: approveSuccess } =
    useWaitForTransactionReceipt({ hash: approveHash });

  // Step 2: Create Task
  const {
    writeContract: createTask,
    data: createHash,
    isPending: createIsPending,
    reset: resetCreate,
  } = useWriteContract();
  const { isLoading: createConfirming, isSuccess: createSuccess } =
    useWaitForTransactionReceipt({ hash: createHash });

  const isPending = approveIsPending || approveConfirming || createIsPending || createConfirming;

  const parsedAmount = (() => {
    try {
      return amount ? parseAmount(ARC_CHAIN_ID, amount) : null;
    } catch {
      return null;
    }
  })();

  const isValidWorker = /^0x[0-9a-fA-F]{40}$/.test(worker);
  const isValidAmount = !!parsedAmount && parsedAmount.raw > 0n;
  const days = parseInt(deadlineDays, 10);
  const isValidDays = !isNaN(days) && days > 0 && days <= 365;
  const canSubmit = isValidWorker && isValidAmount && isValidDays && !isPending;

  const deadlineTimestamp = Math.floor(Date.now() / 1000) + days * 86400;

  function handleApprove() {
    if (!usdcAddress || !parsedAmount) return;
    if (wrongChain) {
      switchChain({ chainId: ARC_CHAIN_ID });
      return;
    }
    approve({
      address: usdcAddress,
      abi: erc20Abi,
      functionName: "approve",
      args: [AGENT_ESCROW_ADDRESS, parsedAmount.raw],
    });
  }

  // Trigger create task once approval confirmed
  if (approveSuccess && !createHash && !createIsPending) {
    createTask({
      address: AGENT_ESCROW_ADDRESS,
      abi: AGENT_ESCROW_ABI,
      functionName: "createTask",
      args: [worker as `0x${string}`, parsedAmount!.raw, BigInt(deadlineTimestamp)],
    });
  }

  if (createSuccess && createHash) {
    toast.success("Task created!", {
      action: {
        label: "View tx",
        onClick: () =>
          window.open(
            buildTxExplorerUrl(ARC_CHAIN_ID, createHash),
            "_blank"
          ),
      },
    });
    onCreated();
    handleClose();
  }

  function handleClose() {
    setWorker("");
    setAmount("");
    setDeadlineDays("7");
    resetApprove();
    resetCreate();
    onClose();
  }

  const ctaLabel = (() => {
    if (!address) return "Connect Wallet";
    if (wrongChain) return "Switch to Arc";
    if (approveIsPending) return "Confirm approval in wallet...";
    if (approveConfirming) return "Approving USDC...";
    if (createIsPending) return "Confirm task creation in wallet...";
    if (createConfirming) return "Confirming...";
    return "Approve & Create Task";
  })();

  return (
    <AnimatePresence>
      {open && (
        <motion.div
          className="fixed inset-0 z-50 flex items-end justify-center"
          initial={{ opacity: 0 }}
          animate={{ opacity: 1 }}
          exit={{ opacity: 0 }}
          onClick={handleClose}
        >
          <div className="absolute inset-0 bg-black/30 backdrop-blur-sm" />
          <motion.section
            className="relative w-full max-w-lg overflow-hidden rounded-t-3xl"
            style={{
              background: "rgba(255,255,255,0.95)",
              backdropFilter: "blur(40px) saturate(200%)",
              WebkitBackdropFilter: "blur(40px) saturate(200%)",
            }}
            initial={{ y: "100%" }}
            animate={{ y: 0 }}
            exit={{ y: "100%" }}
            transition={springs.sheet}
            onClick={(e) => e.stopPropagation()}
          >
            {/* spectral strip */}
            <div
              className="h-1 w-full"
              style={{
                background:
                  "linear-gradient(90deg, #7c3aed, #2563eb, #0891b2, #059669)",
              }}
            />

            {/* drag handle */}
            <div className="flex justify-center pt-3 pb-1">
              <div className="h-1 w-10 rounded-full bg-black/10" />
            </div>

            <div className="px-6 pb-8 pt-3">
              {/* Header */}
              <div className="mb-5 flex items-center justify-between">
                <h2
                  className="display text-xl font-bold"
                  style={{ color: "var(--ink)" }}
                >
                  New Task
                </h2>
                <button
                  onClick={handleClose}
                  className="flex size-8 items-center justify-center rounded-full transition-colors"
                  style={{ background: "var(--surface-muted)" }}
                >
                  <X className="size-4" style={{ color: "var(--muted)" }} />
                </button>
              </div>

              {/* Worker address */}
              <div className="mb-4">
                <label
                  className="mb-1.5 block text-xs font-semibold uppercase tracking-wider"
                  style={{ color: "var(--muted)" }}
                >
                  Worker Address
                </label>
                <input
                  type="text"
                  value={worker}
                  onChange={(e) => setWorker(e.target.value)}
                  placeholder="0x..."
                  className="mono w-full rounded-xl border px-3.5 py-2.5 text-sm outline-none transition-colors focus:ring-2"
                  style={{
                    borderColor: isValidWorker || !worker ? "var(--border)" : "var(--danger)",
                    background: "var(--surface-muted)",
                    color: "var(--ink)",
                  }}
                />
                {worker && !isValidWorker && (
                  <p className="mt-1 text-xs" style={{ color: "var(--danger)" }}>
                    Enter a valid 0x address
                  </p>
                )}
              </div>

              {/* Amount */}
              <div className="mb-4">
                <div className="mb-1.5 flex items-center justify-between">
                  <label
                    className="text-xs font-semibold uppercase tracking-wider"
                    style={{ color: "var(--muted)" }}
                  >
                    Amount
                  </label>
                  {formattedBalance && (
                    <button
                      onClick={() => formattedBalance && setAmount(formattedBalance)}
                      className="text-xs font-semibold"
                      style={{ color: "var(--accent-hover)" }}
                    >
                      Balance: {formattedBalance} · Max
                    </button>
                  )}
                </div>
                <div
                  className="flex items-center rounded-xl px-3.5 py-2"
                  style={{
                    background: "var(--surface-muted)",
                    border: "1px solid var(--border)",
                  }}
                >
                  <input
                    inputMode="decimal"
                    value={amount}
                    onChange={(e) => {
                      const v = e.target.value.replace(/[^0-9.]/g, "");
                      if (v === "" || /^\d*\.?\d*$/.test(v)) setAmount(v);
                    }}
                    placeholder="0.00"
                    className="display flex-1 bg-transparent text-2xl font-bold tabular-nums outline-none placeholder:text-slate-300"
                    style={{ color: "var(--ink)" }}
                  />
                  <span
                    className="ml-2 text-sm font-semibold"
                    style={{ color: "var(--subtle)" }}
                  >
                    USDC
                  </span>
                </div>
              </div>

              {/* Deadline */}
              <div className="mb-6">
                <label
                  className="mb-1.5 block text-xs font-semibold uppercase tracking-wider"
                  style={{ color: "var(--muted)" }}
                >
                  Deadline (days from now)
                </label>
                <div className="flex gap-2">
                  {["1", "3", "7", "14", "30"].map((d) => (
                    <button
                      key={d}
                      onClick={() => setDeadlineDays(d)}
                      className="rounded-xl px-3 py-1.5 text-sm font-semibold transition-all"
                      style={{
                        background:
                          deadlineDays === d
                            ? "var(--accent)"
                            : "var(--surface-muted)",
                        color:
                          deadlineDays === d ? "white" : "var(--ink-2)",
                        border:
                          "1px solid " +
                          (deadlineDays === d
                            ? "var(--accent)"
                            : "var(--border)"),
                      }}
                    >
                      {d}d
                    </button>
                  ))}
                  <input
                    type="number"
                    min={1}
                    max={365}
                    value={deadlineDays}
                    onChange={(e) => setDeadlineDays(e.target.value)}
                    className="w-16 rounded-xl px-2 py-1.5 text-sm outline-none"
                    style={{
                      background: "var(--surface-muted)",
                      border: "1px solid var(--border)",
                      color: "var(--ink)",
                    }}
                  />
                </div>
                <p className="mt-1.5 text-xs" style={{ color: "var(--subtle)" }}>
                  Worker can self-claim 7 days after this deadline if you haven't released
                </p>
              </div>

              {/* CTA */}
              <button
                disabled={!canSubmit && !!address && !wrongChain}
                onClick={wrongChain ? () => switchChain({ chainId: ARC_CHAIN_ID }) : handleApprove}
                className="flex w-full items-center justify-center gap-2 rounded-2xl py-3.5 text-sm font-semibold text-white transition-all hover:scale-[1.01] active:scale-[0.99] disabled:cursor-not-allowed disabled:opacity-40"
                style={{ background: "var(--accent)" }}
              >
                {isPending && <Loader2 className="size-4 animate-spin" />}
                {ctaLabel}
              </button>

              <p className="mt-3 text-center text-xs" style={{ color: "var(--subtle)" }}>
                Step 1 approves USDC spend — step 2 locks it in escrow
              </p>
            </div>
          </motion.section>
        </motion.div>
      )}
    </AnimatePresence>
  );
}
