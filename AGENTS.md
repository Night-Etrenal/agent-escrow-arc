# AgentEscrow

> Built with Arc Studio - money-powered apps in minutes

USDC escrow for AI-agent tasks on Arc. Built and tested on Arc Testnet inside Arc Studio, now deployed on **Arc Mainnet** (chain 5042) at `0x9593B5F6E757A6558C454921b5AFB1fD2Efc5C99` — see README.md.

---

## What This App Does

Lets a client lock USDC for a worker-agent task. The worker submits a result hash onchain; the client approves release. If the client disappears, the worker can self-claim 7 days after the deadline. If no result was submitted by deadline, the client can reclaim.

## Tech Stack

- Frontend: React 18, Vite, TypeScript, Tailwind CSS, Framer Motion
- Web3: wagmi v2, viem v2, ConnectKit
- Contracts: Solidity 0.8.28 + Foundry, OpenZeppelin 5.6.1
- Chain: Arc Testnet (Chain ID: 5042002)
- Token: USDC (6 decimals) — 0x3600000000000000000000000000000000000000
- Design: Arc Light, Space Grotesk + DM Sans

## Deployed Contracts

| Contract | Address | Explorer |
|---|---|---|
| AgentEscrow | 0x53a0445431ae946f45cd53d0737d15dd7e605d97 | https://explorer.testnet.arc.io/address/0x53a0445431ae946f45cd53d0737d15dd7e605d97 |

Deployed on Arc Testnet, constructor arg: USDC `0x3600000000000000000000000000000000000000`.
Deploy tx: `0x3bb01b33d13c4d63ab2b180b5b5e51687d5bd63110b003046d34077924f9076e`

## Key Files

- `src/App.tsx` — app shell, tabs, header
- `src/contract.ts` — ABI + address + types
- `src/components/CreateTaskSheet.tsx` — new task bottom sheet
- `src/components/TaskCard.tsx` — task row with all actions
- `src/components/TaskList.tsx` — reads all tasks from chain
- `contracts/AgentEscrow.sol` — escrow contract
- `contracts/test/AgentEscrow.*.t.sol` — 67 Foundry unit tests

## Decisions

- Pull-payment model: approveRelease/workerClaim accrue to pendingWithdrawals; worker calls withdraw(). Protects against Arc USDC blocklist bricking the payout push.
- Worker self-claim window: deadline + 7 days, so a disappearing client cannot permanently lock funds.
- USDC passed as constructor arg (not hardcoded) for testnet/mainnet portability.
