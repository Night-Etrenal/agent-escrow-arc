# AgentEscrow — USDC escrow for AI-agent work on Arc

**Live on Arc Mainnet.** A client locks USDC for an AI agent (the *worker*), the agent posts a hash of its deliverable onchain, and the client releases payment — with built-in protection for both sides if the other disappears.

- **Live app:** https://night-etrenal.github.io/agent-escrow-arc/
- **Contract (Arc Mainnet, chain 5042):** [`0x9593B5F6E757A6558C454921b5AFB1fD2Efc5C99`](https://explorer.arc.io/address/0x9593B5F6E757A6558C454921b5AFB1fD2Efc5C99) — source verified on [Sourcify](https://repo.sourcify.dev/5042/0x9593B5F6E757A6558C454921b5AFB1fD2Efc5C99) (exact match); verification also forwarded to the Arc explorer
- **Arc Studio project:** https://studio.arc.io/app/794f1d7e-ad0a-4324-866d-edc1a3650141
- **Earlier testnet deployment (Arc Testnet, 5042002):** [`0x53a0445431ae946f45cd53d0737d15dd7e605d97`](https://explorer.testnet.arc.io/address/0x53a0445431ae946f45cd53d0737d15dd7e605d97)

## Why

AI agents are starting to do paid work for people and for other agents, but neither side wants to go first: the client doesn't want to prepay an agent that may never deliver, and the agent doesn't want to work for a client that may never pay. AgentEscrow is the smallest trust-minimised primitive that fixes this using USDC on Arc, where USDC is also the gas token — so an agent only ever needs one asset to work and get paid.

## How it works

```
client ──approve + createTask(worker, amount, deadline)──▶  [USDC locked in AgentEscrow]
worker ──submitResult(taskId, keccak256(deliverable))─────▶  state = Submitted
client ──approveRelease(taskId)───────────────────────────▶  worker credited
worker ──withdraw()───────────────────────────────────────▶  USDC → worker

no result by deadline        → client: reclaim(taskId)      (refund)
client vanishes after submit → worker: workerClaim(taskId)  (7 days after deadline)
```

Design decisions:
- **Pull payments.** Releases credit `pendingWithdrawals`; the worker calls `withdraw()`. A blocklisted/broken recipient can never brick other tasks.
- **Worker self-claim window** (deadline + 7 days) so a disappearing client cannot lock funds forever.
- **Client reclaim** only when nothing was submitted and the deadline has passed.
- **USDC address is a constructor arg**, so the same bytecode runs on Arc Testnet and Arc Mainnet (`0x3600000000000000000000000000000000000000`, 6-decimals ERC-20 interface of native USDC).
- OpenZeppelin `SafeERC20` + `ReentrancyGuard`, custom errors, no owner / no admin keys / no upgradeability.

## Real USDC on Arc Mainnet — end-to-end transactions

Both lifecycle paths were exercised with real USDC through the deployed contract (client `0x65F1C06d13bBC0f040916f38A4218276EF13aF11`, worker agent `0x8AF848A44D06339BC6f286c5ac7CC5E3c6308875`):

| # | Step | Tx |
|---|---|---|
| 0 | Deploy `AgentEscrow(usdc=0x3600…0000)` | [`0x2b7ceb2b…77750b`](https://explorer.arc.io/tx/0x2b7ceb2b8f9339c80ddd74b0f58b2b736f7729f8cecf07a890ec54752e77750b) |
| 1 | Client funds the worker agent wallet with 0.02 USDC for gas | [`0x8792bf5d…381404`](https://explorer.arc.io/tx/0x8792bf5da841d9a3e597dd7d3f08e843a095aa0a4e5b869d859046c7f9381404) |
| 2 | Client `approve`s the escrow to pull 0.2 USDC (ERC-20 USDC) | [`0xee903431…0274f5`](https://explorer.arc.io/tx/0xee903431b6f51c102893b548b1d4371a4e9f631b08e2f88a6670e1aa330274f5) |
| 3 | Task #1 `createTask(worker, 0.10 USDC, now+1h)` — 0.10 USDC locked in escrow | [`0x5827f92f…d05754`](https://explorer.arc.io/tx/0x5827f92fef19d131ee612d37cb19880e90654658fad54861972dbe69ffd05754) |
| 4 | Worker `submitResult(1, 0xe7e4604d…)` — result hash recorded onchain | [`0x121fbb52…d3c50f`](https://explorer.arc.io/tx/0x121fbb527a33cf0f887aa5336bb96636772bdaf1f2b4cb61b1f8440abbd3c50f) |
| 5 | Client `approveRelease(1)` — 0.10 USDC credited to worker | [`0x0e99fa69…a1cabc`](https://explorer.arc.io/tx/0x0e99fa695587842aa96443ec4906b693dfa937838bbb275a3e735ba4e3a1cabc) |
| 6 | Worker `withdraw()` — 0.10 USDC paid out to the worker wallet | [`0x0b2d8414…7bda8f`](https://explorer.arc.io/tx/0x0b2d841422b6e1c128c1fd53b363dbde731701d0c6bda7c1e72f64eac47bda8f) |
| 7 | Task #2 `createTask(worker, 0.10 USDC, now+90s)` — worker never delivers | [`0x9ed541ab…cc6445`](https://explorer.arc.io/tx/0x9ed541ab8e6a4f6cbdfc688fcba0279e063b96957c771356db4869a466cc6445) |
| 8 | Client `reclaim(2)` after deadline — 0.10 USDC refunded to client | [`0x4822610b…5780be`](https://explorer.arc.io/tx/0x4822610bec3128e5cd3ad34d7479382300d666a8903db960c0eaf65a605780be) |
| 9 | Worker returns 0.11 USDC to the client wallet (housekeeping) | [`0x0a7ca80c…92ef88`](https://explorer.arc.io/tx/0x0a7ca80ccf6696a67e57b08331cf558696babf5664122203b1a04d50ac92ef88) |

Task #1 result hash: `0xe7e4604d52949913c45b98db3ab571b570a309d745aa59a79f82ff93f47d8833`. Raw log: [`deployments/arc-mainnet-txs.log`](deployments/arc-mainnet-txs.log).

## Built with Arc Studio

The whole app was built inside [Arc Studio](https://studio.arc.io):
1. **Specified & generated** the contract, the React/wagmi frontend and the deploy scripts in Studio (see `AGENTS.md`, which Studio maintains as the project brief).
2. **Tested in Studio** — Foundry suite under `contracts/test/`: 64 unit/revert/fuzz tests plus 3 stateful invariants (128k randomized calls: escrow balance always covers active tasks, total USDC conserved, pending withdrawals never exceed balance). 67 checks total; `forge test` reports 65 because it counts the invariant suite as one.
3. **Security-reviewed in Studio** — two review passes on the contract, no open findings.
4. **Deployed to Arc Testnet from Studio** and exercised through the Studio preview (`src/tracing.ts` / `src/console-capture.ts` are Studio's in-preview transaction tracing).
5. **Promoted to Arc Mainnet** with Foundry (Studio deploys to testnet only), the same source, and the USDC address from Studio's onchain-facts registry (`src/onchain-facts.ts`). The frontend was pointed at chain 5042 and the mainnet contract.

## Run it

Requirements: [Bun](https://bun.sh) ≥ 1.0 (or Node 20+ with npm) and [Foundry](https://getfoundry.sh).

```bash
bun install
forge test                      # contract tests
bun run dev                     # local frontend (Arc Mainnet, chain 5042)
VITE_BASE=/agent-escrow-arc/ bun run build   # static build used for GitHub Pages
```

Connect an injected wallet (MetaMask, Rabby…) — the app will offer to switch to Arc (chain 5042, RPC `https://rpc.mainnet.arc.io`). USDC is the gas token on Arc, so a few cents of USDC covers all gas.

Deploy your own copy:

```bash
forge create contracts/AgentEscrow.sol:AgentEscrow \
  --rpc-url https://rpc.mainnet.arc.io --legacy --broadcast \
  --private-key $YOUR_KEY \
  --constructor-args 0x3600000000000000000000000000000000000000
```

## Tech stack

Solidity 0.8.28 · Foundry · OpenZeppelin 5.6.1 · React 18 · Vite · TypeScript · Tailwind · wagmi v2 / viem v2 · ConnectKit.

## License

MIT
