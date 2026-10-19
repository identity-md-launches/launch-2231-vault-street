# Vendored dependencies

- `lib/openzeppelin-contracts`: [OpenZeppelin/openzeppelin-contracts v5.4.0](https://github.com/OpenZeppelin/openzeppelin-contracts/tree/v5.4.0).
  Source archive SHA-256: `b89829be48bc501051002191733268a93ef6e238a4bb65d8fd1cbdf3969050d1`.
  Vendored 6 files, unmodified; licenses are included.

- `lib/forge-std`: [foundry-rs/forge-std v1.9.7](https://github.com/foundry-rs/forge-std/tree/v1.9.7).
  Source archive SHA-256: `45157353ab49eab01d294565866731e599b32401757229689ee459aa26b7ee94`.
  Vendored 30 files, unmodified; licenses are included.

OpenZeppelin includes only the ERC-20 source dependency closure and its MIT license.
Forge Std includes its Solidity test helpers and both upstream licenses.
No dependency installation, git submodule, FFI, or network access is needed to build or test.
