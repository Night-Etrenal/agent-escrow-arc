import { useState, useCallback } from "react";
import { ConnectKitButton } from "connectkit";
import { useAccount } from "wagmi";
import { Plus, ExternalLink, Zap } from "lucide-react";
import { CreateTaskSheet } from "@/components/CreateTaskSheet";
import { TaskList } from "@/components/TaskList";

type Tab = "all" | "client" | "worker";

export default function App() {
  const { address } = useAccount();
  const [sheetOpen, setSheetOpen] = useState(false);
  const [tab, setTab] = useState<Tab>("all");
  const [refreshKey, setRefreshKey] = useState(0);

  const handleActionDone = useCallback(() => {
    setRefreshKey((k) => k + 1);
  }, []);

  return (
    <div
      className="min-h-dvh"
      style={{ background: "var(--bg-gradient)" }}
    >
      {/* Sticky header */}
      <header
        className="sticky top-0 z-30 border-b px-4 py-3"
        style={{
          background: "rgba(255,255,255,0.80)",
          backdropFilter: "blur(20px) saturate(200%)",
          WebkitBackdropFilter: "blur(20px) saturate(200%)",
          borderColor: "var(--border)",
        }}
      >
        <div className="mx-auto flex max-w-2xl items-center justify-between">
          <div className="flex items-center gap-2.5">
            <div
              className="flex size-8 items-center justify-center rounded-xl"
              style={{ background: "var(--accent)" }}
            >
              <Zap className="size-4 text-white" />
            </div>
            <div>
              <h1
                className="display text-base font-bold leading-none"
                style={{ color: "var(--ink)" }}
              >
                AgentEscrow
              </h1>
              <p className="text-[10px]" style={{ color: "var(--muted)" }}>
                USDC escrow for AI tasks · Arc Mainnet
              </p>
            </div>
          </div>

          <div className="flex items-center gap-2">
            <a
              href="https://explorer.arc.io/address/0x9593B5F6E757A6558C454921b5AFB1fD2Efc5C99"
              target="_blank"
              rel="noreferrer"
              className="hidden items-center gap-1 rounded-lg px-2.5 py-1.5 text-xs font-semibold sm:flex"
              style={{
                background: "var(--surface-muted)",
                color: "var(--muted)",
                border: "1px solid var(--border)",
              }}
            >
              Contract
              <ExternalLink className="size-3" />
            </a>
            <ConnectKitButton />
          </div>
        </div>
      </header>

      {/* Main content */}
      <main className="mx-auto max-w-2xl px-4 py-6">
        {/* Hero card */}
        <div
          className="mb-6 rounded-3xl p-5"
          style={{
            background: "var(--surface-strong)",
            border: "1px solid var(--border)",
            boxShadow: "0 4px 24px rgba(18,45,69,0.06)",
          }}
        >
          <p
            className="mb-1 text-xs font-semibold uppercase tracking-widest"
            style={{ color: "var(--muted)" }}
          >
            How it works
          </p>
          <div className="mt-3 grid grid-cols-1 gap-3 sm:grid-cols-3">
            {[
              {
                n: "1",
                title: "Create",
                desc: "Lock USDC for a worker with a deadline",
              },
              {
                n: "2",
                title: "Submit",
                desc: "Worker posts a result hash onchain",
              },
              {
                n: "3",
                title: "Release",
                desc: "Client approves — or worker self-claims after 7 days",
              },
            ].map((s) => (
              <div
                key={s.n}
                className="rounded-2xl p-3"
                style={{ background: "var(--surface-muted)" }}
              >
                <span
                  className="display mb-1 block text-2xl font-bold"
                  style={{ color: "var(--accent)" }}
                >
                  {s.n}
                </span>
                <p
                  className="text-sm font-semibold"
                  style={{ color: "var(--ink)" }}
                >
                  {s.title}
                </p>
                <p className="text-xs" style={{ color: "var(--subtle)" }}>
                  {s.desc}
                </p>
              </div>
            ))}
          </div>
        </div>

        {/* Tabs + New Task */}
        <div className="mb-4 flex items-center justify-between">
          <div
            className="flex gap-1 rounded-xl p-1"
            style={{ background: "var(--surface-muted)" }}
          >
            {(["all", "client", "worker"] as Tab[]).map((t) => (
              <button
                key={t}
                onClick={() => setTab(t)}
                className="rounded-lg px-3.5 py-1.5 text-xs font-semibold capitalize transition-all"
                style={
                  tab === t
                    ? { background: "white", color: "var(--ink)", boxShadow: "0 1px 4px rgba(0,0,0,0.08)" }
                    : { color: "var(--subtle)" }
                }
              >
                {t === "all" ? "All Tasks" : t === "client" ? "As Client" : "As Worker"}
              </button>
            ))}
          </div>

          <button
            onClick={() => setSheetOpen(true)}
            className="flex items-center gap-1.5 rounded-xl px-3.5 py-2 text-xs font-semibold text-white transition-all hover:scale-[1.03] active:scale-[0.98]"
            style={{ background: "var(--accent)" }}
          >
            <Plus className="size-3.5" />
            New Task
          </button>
        </div>

        {/* Task list */}
        <TaskList
          filter={tab}
          address={address}
          refreshKey={refreshKey}
          onActionDone={handleActionDone}
        />
      </main>

      {/* Create task sheet */}
      <CreateTaskSheet
        open={sheetOpen}
        onClose={() => setSheetOpen(false)}
        onCreated={handleActionDone}
      />
    </div>
  );
}
