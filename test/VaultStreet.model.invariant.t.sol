// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {VaultStreet} from "../src/VaultStreet.sol";

/// @dev Drives VaultStreet against an independent ghost model of balances and allowances. Unlike the
/// closed-set handler, actors are discovered from fuzzed addresses (including the deployer and the
/// token itself), and every failure path (overspend, overdraw, zero receiver, zero spender, zero
/// owner) is exercised inside the same random sequences and must revert without touching state.
contract VaultStreetModelHandler is Test {
    VaultStreet private immutable token;

    address[] public actors;
    mapping(address => bool) private known;
    mapping(address => uint256) public ghostBalance;
    mapping(address => mapping(address => uint256)) public ghostAllowance;

    uint256 public ghostMoved;
    uint256 public expectedReverts;
    uint256 public succeededTransfers;

    constructor(VaultStreet token_, address deployer, uint256 supply) {
        token = token_;
        _track(deployer);
        ghostBalance[deployer] = supply;
        _track(address(token_));
        _track(makeAddr("model alice"));
        _track(makeAddr("model bob"));
    }

    function actorCount() external view returns (uint256) {
        return actors.length;
    }

    /// @dev Either an existing actor or, one time in four, a fresh fuzzed address joining the set.
    function _actor(uint256 seed, address fresh) private returns (address a) {
        if (seed % 4 == 0 && fresh != address(0)) {
            _track(fresh);
            return fresh;
        }
        return actors[seed % actors.length];
    }

    function _track(address a) private {
        if (!known[a]) {
            known[a] = true;
            actors.push(a);
        }
    }

    function transfer(uint256 fromSeed, uint256 toSeed, address freshTo, uint256 amount) external {
        address from = actors[fromSeed % actors.length];
        address to = _actor(toSeed, freshTo);
        amount = bound(amount, 0, ghostBalance[from]);
        vm.prank(from);
        assertTrue(token.transfer(to, amount), "transfer returned false");
        ghostBalance[from] -= amount;
        ghostBalance[to] += amount;
        ghostMoved += amount;
        ++succeededTransfers;
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, address freshSpender, uint256 amount) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = _actor(spenderSeed, freshSpender);
        // Mix exact edge values with arbitrary ones.
        if (amount % 5 == 0) amount = type(uint256).max;
        else if (amount % 5 == 1) amount = 0;
        vm.prank(owner);
        assertTrue(token.approve(spender, amount), "approve returned false");
        ghostAllowance[owner][spender] = amount;
    }

    function transferFrom(uint256 fromSeed, uint256 toSeed, address freshTo, uint256 spenderSeed, uint256 amount)
        external
    {
        address from = actors[fromSeed % actors.length];
        address to = _actor(toSeed, freshTo);
        address spender = actors[spenderSeed % actors.length];
        uint256 allowed = ghostAllowance[from][spender];
        uint256 cap = allowed < ghostBalance[from] ? allowed : ghostBalance[from];
        amount = bound(amount, 0, cap);
        vm.prank(spender);
        assertTrue(token.transferFrom(from, to, amount), "transferFrom returned false");
        if (allowed != type(uint256).max) ghostAllowance[from][spender] = allowed - amount;
        ghostBalance[from] -= amount;
        ghostBalance[to] += amount;
        ghostMoved += amount;
        ++succeededTransfers;
    }

    function overdrawTransfer(uint256 fromSeed, uint256 toSeed, uint256 excess) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 have = ghostBalance[from];
        uint256 amount = have + bound(excess, 1, type(uint256).max - have);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, have, amount));
        vm.prank(from);
        token.transfer(to, amount);
        ++expectedReverts;
    }

    function overspendAllowance(uint256 fromSeed, uint256 toSeed, uint256 spenderSeed, uint256 excess) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        uint256 allowed = ghostAllowance[from][spender];
        if (allowed == type(uint256).max) return;
        uint256 amount = allowed + bound(excess, 1, type(uint256).max - allowed);
        // Allowance is checked before balance, so an overspend always reports the allowance.
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, allowed, amount)
        );
        vm.prank(spender);
        token.transferFrom(from, to, amount);
        ++expectedReverts;
    }

    function allowedButOverdrawn(uint256 fromSeed, uint256 toSeed, uint256 spenderSeed, uint256 excess) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        uint256 have = ghostBalance[from];
        uint256 allowed = ghostAllowance[from][spender];
        if (allowed <= have) return;
        uint256 amount = bound(excess, have + 1, allowed);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, have, amount));
        vm.prank(spender);
        token.transferFrom(from, to, amount);
        ++expectedReverts;
    }

    function transferToZero(uint256 fromSeed, uint256 amount) external {
        address from = actors[fromSeed % actors.length];
        amount = bound(amount, 0, ghostBalance[from]);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(from);
        token.transfer(address(0), amount);
        ++expectedReverts;
    }

    function transferFromToZero(uint256 fromSeed, uint256 spenderSeed, uint256 amount) external {
        address from = actors[fromSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        uint256 allowed = ghostAllowance[from][spender];
        uint256 cap = allowed < ghostBalance[from] ? allowed : ghostBalance[from];
        amount = bound(amount, 0, cap);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(from, address(0), amount);
        ++expectedReverts;
    }

    function transferFromZeroOwner(uint256 toSeed, uint256 spenderSeed) external {
        address to = actors[toSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidApprover.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(address(0), to, 0);
        ++expectedReverts;
    }

    function approveZeroSpender(uint256 ownerSeed, uint256 amount) external {
        address owner = actors[ownerSeed % actors.length];
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        vm.prank(owner);
        token.approve(address(0), amount);
        ++expectedReverts;
    }
}

contract VaultStreetModelInvariantTest is StdInvariant, Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 1e18;

    VaultStreet private token;
    VaultStreetModelHandler private handler;
    address private deployer;

    function setUp() public {
        deployer = makeAddr("model deployer");
        vm.prank(deployer);
        token = new VaultStreet();
        handler = new VaultStreetModelHandler(token, deployer, SUPPLY);

        bytes4[] memory selectors = new bytes4[](10);
        selectors[0] = VaultStreetModelHandler.transfer.selector;
        selectors[1] = VaultStreetModelHandler.approve.selector;
        selectors[2] = VaultStreetModelHandler.transferFrom.selector;
        selectors[3] = VaultStreetModelHandler.overdrawTransfer.selector;
        selectors[4] = VaultStreetModelHandler.overspendAllowance.selector;
        selectors[5] = VaultStreetModelHandler.allowedButOverdrawn.selector;
        selectors[6] = VaultStreetModelHandler.transferToZero.selector;
        selectors[7] = VaultStreetModelHandler.transferFromToZero.selector;
        selectors[8] = VaultStreetModelHandler.transferFromZeroOwner.selector;
        selectors[9] = VaultStreetModelHandler.approveZeroSpender.selector;
        targetContract(address(handler));
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 64
    /// forge-config: default.invariant.fail-on-revert = true
    function invariant_supplyNeverChanges() public view {
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.INITIAL_SUPPLY(), SUPPLY);
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 64
    /// forge-config: default.invariant.fail-on-revert = true
    function invariant_everyBalanceMatchesTheModelAndSumsToSupply() public view {
        uint256 n = handler.actorCount();
        uint256 sum;
        for (uint256 i; i < n; ++i) {
            address a = handler.actors(i);
            uint256 bal = token.balanceOf(a);
            assertEq(bal, handler.ghostBalance(a), "balance diverged from the model");
            sum += bal;
        }
        // Every unit is held by a tracked actor: nothing leaked to an untracked address.
        assertEq(sum, SUPPLY, "tracked balances do not account for the supply");
        assertEq(token.balanceOf(address(0)), 0);
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 64
    /// forge-config: default.invariant.fail-on-revert = true
    function invariant_everyAllowanceMatchesTheModel() public view {
        uint256 n = handler.actorCount();
        for (uint256 i; i < n; ++i) {
            address owner = handler.actors(i);
            for (uint256 j; j < n; ++j) {
                address spender = handler.actors(j);
                assertEq(token.allowance(owner, spender), handler.ghostAllowance(owner, spender), "allowance diverged");
            }
            assertEq(token.allowance(owner, address(0)), 0, "zero spender acquired an allowance");
            assertEq(token.allowance(address(0), owner), 0, "zero owner acquired an allowance");
        }
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 64
    /// forge-config: default.invariant.fail-on-revert = true
    /// @dev Guards against a vacuous run: each sequence must have moved tokens and hit failure paths.
    function afterInvariant() public view {
        assertGt(handler.succeededTransfers(), 0, "no transfer succeeded in this sequence");
        assertGt(handler.expectedReverts(), 0, "no failure path was exercised in this sequence");
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 64
    /// forge-config: default.invariant.fail-on-revert = true
    function invariant_tokenHoldsNoEtherAndMetadataIsFixed() public view {
        assertEq(address(token).balance, 0);
        assertEq(token.decimals(), 18);
        assertEq(token.name(), "Vault Street");
        assertEq(token.symbol(), "VST");
    }
}
