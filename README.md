# Vault Street (VST)

Vault Street is a fixed-supply ERC-20. Its constructor mints **1,000,000,000 VST**
with **18 decimals**, entirely to the immediate deployer. The total supply in
smallest units is **1000000000000000000000000000** (`10^27`).

The deployable contract is [`VaultStreet`](src/VaultStreet.sol), built on the
vendored OpenZeppelin Contracts v5.4.0 ERC-20 implementation. There are no
application contracts to deploy. Contracts under `test/` are test helpers only.

## Behavior and assumptions

- Name: `Vault Street`; symbol: `VST`; decimals: `18`.
- `INITIAL_SUPPLY` is the named constant for the one-time constructor mint.
- Ordinary ERC-20 transfers move the exact amount, with no token transfer tax,
  fees, rebasing, or automatic allocation.
- Successful `transfer`, `approve`, and `transferFrom` calls return `true`.
  Invalid operations revert with OpenZeppelin's ERC-6093 custom errors.
- Transfers to the zero address and approvals to a zero spender revert.
  Zero-amount transfers between valid addresses and self-transfers are supported.
- Finite allowances decrease when spent. `type(uint256).max` represents an
  unlimited allowance and is not decreased. `approve` replaces the allowance;
  `approve(spender, 0)` revokes it.
- Minting emits `Transfer(address(0), deployer, INITIAL_SUPPLY)`. Transfers emit
  `Transfer`, and explicit approvals emit `Approval`. As in OpenZeppelin v5,
  `transferFrom` does not emit an additional `Approval` for allowance consumption.
- There is no owner, minter role, public burn, pause, blocklist, confiscation,
  upgrade mechanism, permit, or initializer. The deployer has no special powers
  after receiving the supply. The token makes no external calls.
- The token has no payable entry point or asset recovery function. Tokens sent
  to the token contract itself cannot be recovered. Integrators should use
  intended recipient addresses and only grant allowances to trusted spenders.
  When replacing a nonzero allowance, setting it to zero first and confirming
  that transaction limits the standard ERC-20 allowance replacement race.

## Deployment parameters

| Parameter | Value |
| --- | --- |
| Source / contract | `src/VaultStreet.sol:VaultStreet` |
| Target chain supplied by the assignment | Robinhood Chain, chain ID `4663` |
| Constructor arguments | None (`[]`) |
| ETH sent with deployment | None |
| Initial recipient | Immediate constructor `msg.sender` |
| Total supply, smallest units | `1000000000000000000000000000` |
| Solidity compiler | `0.8.26` |
| EVM target | `cancun` |
| Optimizer | Enabled, 200 runs |
| Bytecode metadata hash | `none` |

Deploy the creation bytecode built with the root `foundry.toml`, without appended
constructor arguments. When the launch factory creates the contract, the
factory receives the entire supply; the transaction origin receives none from
the constructor. No initialization transaction, predeployed dependency,
external service, linked library, or owner address is needed. CREATE2 deployment
is tested locally. The launch operator is responsible for using the intended
chain and checking that it supports the configured EVM target.

The supplied launch policy assigns distribution to the factory: 10% to its
Merkle distributor, 80% to the native-ETH pool, and the remaining 10% to
`0x612a9bb008e16ef2d24f41dae9fc661831d93367`. The supplied pool policy uses fee
`12500` (1.25%), tick spacing `60`, and initial market capitalization
`10000000000000000000` wei (10 ETH). The pool fee is separate from token transfers,
which have no fee. These are factory/manifest parameters, not token constructor
parameters or token-enforced allocations. The token does not reserve or send any
allocation during construction.

The launch pipeline creates its manifest separately and derives the opening
pool price. This repository supplies the token source and build artifacts;
it does not contain a launch manifest or a broadcasting script.

## After launch

There are no token settings to configure and no token administrator to operate.
The launch operator handles distribution, liquidity initialization, and publishing
the deployed address and verified source. Immediately after construction, it
should verify the metadata, `totalSupply()`, and the factory's full initial
balance before distribution. It should then verify the factory's distribution
receipts against the launch policy.

Holders control transfers and allowances. Indexers should query `allowance`
when they need its current value rather than infer it solely from `Approval`
events. No operator can recover mistaken transfers, reverse approvals made to
malicious spenders, freeze balances, or patch the deployed token. Chain operation
and transaction inclusion remain responsibilities of the target network.

## Build and test

Foundry and Solidity 0.8.26 are required. All Solidity dependencies and their
licenses are ordinary files in `lib/`; their versions and source archive hashes
are recorded in [`DEPENDENCIES.md`](DEPENDENCIES.md). With the pinned compiler
available, building and testing require no network, environment secrets, RPC,
FFI, filesystem permissions, or dependency installation.

```sh
forge build
FOUNDRY_FUZZ_SEED=0x560c186c13e40b7265e033d3d02c67b596b1ec46ba04a3e1a04e6f0924c8d17e forge test
forge fmt --check
```

Local validation passed: `forge build`, the seeded `forge test` command above
(35 tests, 0 failures), and `forge fmt --check`. The invariant run completed
8,192 calls with no reverts. The optimized runtime is 1,753 bytes and has no
external library link references.

The tests cover metadata and the constructor mint event; direct and CREATE2
factory deployment; exact factory distribution, claims, and pool-side token
transfers; standard transfers and approvals; insufficient balances and
allowances; revocation; zero addresses; self-transfers; infinite allowances;
atomic rollback of allowance on failure; absent administrative entry points;
native-ETH rejection; and runtime size/forbidden opcode checks.

Five fuzz tests run 1,000 cases each. A stateful invariant test runs 128 sequences
of 64 operations over four holders, checking transfer accounting, allowance
consumption, fixed supply, and conservation of all balances. Tests are isolated
and do not read or modify environment variables. In tests, `ether` is only
Solidity's `10^18` unit shorthand for token amounts unless explicitly sending ETH.

The local factory/pool actors exercise token behavior; they are not a real
Uniswap PoolManager and do not establish full AMM integration. The supplied
protected checks refer to a separate launch harness and manifest configuration
that the independent verifier supplies. Security review here consists of source
inspection and Foundry unit, fuzz, and invariant tests; Slither and Mythril are
not part of this local validation. These checks are not an independent audit.
