import { useReadContract } from "wagmi";
import { createPublicClient, http } from "viem";
import { useQuery } from "@tanstack/react-query";
import { Loader2, Inbox } from "lucide-react";
import {
  AGENT_ESCROW,
  AGENT_ESCROW_ABI,
  AGENT_ESCROW_ADDRESS,
  ARC_CHAIN_ID,
  TaskData,
  TaskState,
} from "@/contract";
import { requireChain } from "@/onchain-facts";
import { TaskCard } from "./TaskCard";

interface Props {
  filter: "all" | "client" | "worker";
  address?: string;
  refreshKey: number;
  onActionDone: () => void;
}

export function TaskList({ filter, address, refreshKey, onActionDone }: Props) {
  const { data: count, isLoading: countLoading } = useReadContract({
    ...AGENT_ESCROW,
    functionName: "taskCount",
    chainId: ARC_CHAIN_ID,
    query: { refetchInterval: 8000 },
  });

  const taskCount = count != null ? Number(count) : 0;

  const chainInfo = requireChain(ARC_CHAIN_ID);

  const { data: tasks = [], isLoading: tasksLoading } = useQuery<
    { id: bigint; task: TaskData }[]
  >({
    queryKey: ["tasks", taskCount, refreshKey],
    enabled: taskCount > 0,
    refetchInterval: 8000,
    queryFn: async () => {
      const rpcClient = createPublicClient({
        transport: http(chainInfo.rpcUrls[0]),
      });
      const results: { id: bigint; task: TaskData }[] = [];
      for (let i = 1; i <= taskCount; i++) {
        try {
          const raw = (await rpcClient.readContract({
            address: AGENT_ESCROW_ADDRESS,
            abi: AGENT_ESCROW_ABI,
            functionName: "getTask",
            args: [BigInt(i)],
          })) as readonly [
            string,
            string,
            bigint,
            bigint,
            bigint,
            `0x${string}`,
            number,
          ];
          const stateValue = raw[6] in TaskState ? raw[6] : TaskState.Created;
          results.push({
            id: BigInt(i),
            task: {
              client: raw[0],
              worker: raw[1],
              amount: raw[2],
              deadline: raw[3],
              workerClaimAfter: raw[4],
              resultHash: raw[5],
              state: stateValue,
            },
          });
        } catch {
          // skip tasks that fail to read
        }
      }
      return results;
    },
  });

  const filtered = tasks.filter(({ task }) => {
    if (filter === "client" && address)
      return task.client.toLowerCase() === address.toLowerCase();
    if (filter === "worker" && address)
      return task.worker.toLowerCase() === address.toLowerCase();
    return true;
  });

  const sorted = [...filtered].reverse();

  if (countLoading || tasksLoading) {
    return (
      <div className="flex items-center justify-center py-16">
        <Loader2
          className="size-6 animate-spin"
          style={{ color: "var(--muted)" }}
        />
      </div>
    );
  }

  if (sorted.length === 0) {
    return (
      <div className="flex flex-col items-center justify-center gap-3 py-16">
        <Inbox className="size-8" style={{ color: "var(--border-strong)" }} />
        <p className="text-sm" style={{ color: "var(--muted)" }}>
          {filter === "all"
            ? "No tasks yet"
            : "No tasks for your address"}
        </p>
      </div>
    );
  }

  return (
    <div className="flex flex-col gap-3">
      {sorted.map(({ id, task }) => (
        <TaskCard
          key={id.toString()}
          taskId={id}
          task={task}
          onActionDone={onActionDone}
        />
      ))}
    </div>
  );
}
