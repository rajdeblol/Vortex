# LiveYieldOracle – Autonomous Cross-Chain Yield Optimizer on Ritual Chain

Fully on-chain autonomous yield optimizer using **Ritual native primitives only** (no off-chain keepers).

## Architecture Overview

- **Ritual Chain (Chain ID 1979)**: Brain / Oracle
  - `Scheduler` at `0x56e776BAE2DD60664b69Bd5F865F1180ffB7D58B`
  - `HTTP` precompile `0x0801` + `LongHTTP` `0x0805`
  - `ONNX` precompile `0x0800`
  - `RitualWallet` `0x532F0dF0896F353d8C3DD8cc134e8129DA2a3948`
- **Base Sepolia**: Real USDC vault (`0x036cbd53842c5426634e7929541ec2318f3dcf7e`)
- **Ritual testnet**: MockUSDC + Vault for pure on-chain testing

## Prerequisites

1. **Foundry** (already installed in this repo)
2. **Private key** with testnet funds
3. **Ritual testnet faucet** → https://faucet.ritualfoundation.org

## Exact Deployment & Setup Steps

### 1. Get Testnet Funds

```bash
# Ritual testnet
curl -X POST https://faucet.ritualfoundation.org/api/claim \
  -H "Content-Type: application/json" \
  -d '{"address":"YOUR_ADDRESS"}'

# Base Sepolia (for real USDC testing)
# Use https://www.coinbase.com/faucets or https://sepoliafaucet.com
```

### 2. Deploy to Ritual (Recommended First Step)

```bash
cd /Users/raj/LiveYieldOracle

# Set your private key
export PRIVATE_KEY=0x...

# Deploy everything on Ritual
forge script script/DeployRitual.s.sol:DeployRitual \
  --rpc-url https://rpc.ritualfoundation.org \
  --broadcast \
  --private-key $PRIVATE_KEY
```

Save the `LiveYieldOracle` address (you'll need it for the next steps).

### 3. Fund the RitualWallet (Critical)

The Scheduler needs gas from the RitualWallet.

```bash
# Using the helper script
ORACLE=0xYourOracleAddress ./scripts/ritual-cli.sh fund 1000000000000000000
# or manually:
cast send $ORACLE "fundRitualWallet()" \
  --value 1ether \
  --rpc-url https://rpc.ritualfoundation.org \
  --private-key $PRIVATE_KEY
```

### 4. Start the Autonomous Scheduler

```bash
# Run every 100 blocks (~20 minutes on Ritual)
ORACLE=0xYourOracleAddress ./scripts/ritual-cli.sh schedule 100
```

### 5. Verify State

```bash
ORACLE=0xYourOracleAddress ./scripts/ritual-cli.sh state
```

You should see:
- `currentTargets`
- `lastUpdateBlock` / `lastUpdateTimestamp`
- `schedulerJobId`

---

## How the Autonomous Tick Works

1. Scheduler calls `tick()` every N blocks
2. `tick()` calls HTTP precompile → fetches live APYs
3. Converts yield vector → RitualTensor
4. Calls ONNX precompile with the tensor
5. Stores new allocation weights (basis points, sum = 10000)
6. Emits `RebalanceSuggested` + `YieldsFetched`

## Swapping the ONNX Model

1. Train a small regression model that takes `[apy, vol, ...]` and outputs allocation weights.
2. Export to ONNX.
3. Upload the model to Ritual (via their model registry or direct precompile registration).
4. Call `setModelVersion(bytes32 newVersion)` on the oracle.
5. Update the tensor encoding/decoding logic in `_runOnnxInference` if the model signature changes.

**Tiny example model spec** (for reference):

- **Input**: float32 tensor of shape `[N, 2]` (APY + volatility per protocol)
- **Output**: float32 tensor of shape `[N]` → softmax → scaled to basis points

## Base Sepolia Deployment (Real USDC)

```bash
forge script script/DeployBase.s.sol:DeployBase \
  --rpc-url base_sepolia \
  --broadcast \
  --private-key $PRIVATE_KEY
```

Update the `oracle` address in `BaseVault` later to point at a read-only Ritual oracle view if desired.

## Key Files

| File | Purpose |
|------|---------|
| `src/LiveYieldOracle.sol` | Core autonomous oracle with all Ritual precompiles |
| `src/RitualVault.sol` | Non-custodial vault on Ritual |
| `src/BaseVault.sol` | Non-custodial vault on Base Sepolia |
| `src/MockUSDC.sol` | Test USDC on Ritual |
| `script/DeployRitual.s.sol` | Ritual deployment |
| `script/DeployBase.s.sol` | Base Sepolia deployment |
| `scripts/encode.ts` | Tensor + HTTP encoding helpers (viem) |
| `scripts/ritual-cli.sh` | One-command funding / scheduling / state |

## Security Notes

- `tick()` is **only** callable by the Scheduler precompile.
- Owner can pause, update protocols, change model version, and manage RitualWallet.
- ECIES secret storage and passkey auth skeletons are included for future encrypted flows.

## Next Steps / Production Hardening

- Replace mock yield fetching with real JSON parsing from DefiLlama / protocol APIs.
- Implement proper RitualTensor encoding/decoding.
- Add rebalancing executor that consumes `RebalanceSuggested` events.
- Add comprehensive tests and invariant checks.

---

**Ready to deploy.** All Ritual-specific addresses and precompile patterns are hardcoded exactly as specified. Good luck on Ritual testnet! 🚀