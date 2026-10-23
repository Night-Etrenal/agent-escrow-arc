import artifact from "../contracts/out/AgentEscrow.sol/AgentEscrow.json";

export const AGENT_ESCROW_ADDRESS =
  "0x9593B5F6E757A6558C454921b5AFB1fD2Efc5C99" as const;

export const AGENT_ESCROW_ABI = artifact.abi;

export const AGENT_ESCROW = {
  address: AGENT_ESCROW_ADDRESS,
  abi: AGENT_ESCROW_ABI,
} as const;

export const ARC_CHAIN_ID = 5042; // Arc mainnet

// TaskState enum (matches contract)
export enum TaskState {
  Created = 0,
  Submitted = 1,
  Released = 2,
  Reclaimed = 3,
}

export const TASK_STATE_LABEL: Record<TaskState, string> = {
  [TaskState.Created]: "Open",
  [TaskState.Submitted]: "Submitted",
  [TaskState.Released]: "Released",
  [TaskState.Reclaimed]: "Reclaimed",
};

export const TASK_STATE_COLOR: Record<
  TaskState,
  { bg: string; text: string }
> = {
  [TaskState.Created]: { bg: "rgba(26,128,71,0.10)", text: "var(--success)" },
  [TaskState.Submitted]: {
    bg: "rgba(16,97,166,0.12)",
    text: "var(--accent-hover)",
  },
  [TaskState.Released]: {
    bg: "rgba(26,128,71,0.14)",
    text: "var(--success)",
  },
  [TaskState.Reclaimed]: {
    bg: "rgba(139,132,156,0.14)",
    text: "var(--muted)",
  },
};

export interface TaskData {
  client: string;
  worker: string;
  amount: bigint;
  deadline: bigint;
  workerClaimAfter: bigint;
  resultHash: string;
  state: TaskState;
}
