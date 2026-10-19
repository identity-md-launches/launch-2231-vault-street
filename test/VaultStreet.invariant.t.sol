// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {VaultStreet} from "../src/VaultStreet.sol";

/// @dev Exercises arbitrary sequences over a closed set of holders, including self-transfers.
contract VaultStreetHandler is Test {
    VaultStreet private immutable token;
    address[4] private holders;

    constructor(VaultStreet token_) {
        token = token_;
        holders[0] = makeAddr("holder zero");
        holders[1] = makeAddr("holder one");
        holders[2] = makeAddr("holder two");
        holders[3] = makeAddr("holder three");
    }

    function holder(uint256 index) external view returns (address) {
        return holders[index];
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        address from = holders[fromSeed % holders.length];
        address to = holders[toSeed % holders.length];
        uint256 fromBefore = token.balanceOf(from);
        uint256 toBefore = token.balanceOf(to);
        amount = bound(amount, 0, fromBefore);
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        _checkBalances(from, to, fromBefore, toBefore, amount);
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amount) external {
        address owner = holders[ownerSeed % holders.length];
        address spender = holders[spenderSeed % holders.length];
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        assertEq(token.allowance(owner, spender), amount);
    }

    function transferFrom(uint256 fromSeed, uint256 toSeed, uint256 spenderSeed, uint256 amount) external {
        address from = holders[fromSeed % holders.length];
        address to = holders[toSeed % holders.length];
        address spender = holders[spenderSeed % holders.length];
        uint256 fromBefore = token.balanceOf(from);
        uint256 toBefore = token.balanceOf(to);
        uint256 approved = token.allowance(from, spender);
        amount = bound(amount, 0, approved < fromBefore ? approved : fromBefore);
        vm.prank(spender);
        assertTrue(token.transferFrom(from, to, amount));
        _checkBalances(from, to, fromBefore, toBefore, amount);
        assertEq(token.allowance(from, spender), approved == type(uint256).max ? approved : approved - amount);
    }

    function _checkBalances(address from, address to, uint256 fromBefore, uint256 toBefore, uint256 amount)
        private
        view
    {
        assertEq(token.balanceOf(from), from == to ? fromBefore : fromBefore - amount);
        assertEq(token.balanceOf(to), from == to ? toBefore : toBefore + amount);
    }
}

contract VaultStreetInvariantTest is StdInvariant, Test {
    uint256 private constant SUPPLY = 1_000_000_000_000_000_000_000_000_000;
    VaultStreet private token;
    VaultStreetHandler private handler;

    function setUp() public {
        token = new VaultStreet();
        handler = new VaultStreetHandler(token);
        for (uint256 i; i < 4; ++i) {
            token.transfer(handler.holder(i), SUPPLY / 4);
        }

        bytes4[] memory selectors = new bytes4[](3);
        selectors[0] = VaultStreetHandler.transfer.selector;
        selectors[1] = VaultStreetHandler.approve.selector;
        selectors[2] = VaultStreetHandler.transferFrom.selector;
        targetContract(address(handler));
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    function invariant_supplyIsFixedAndAllBalancesAreAccountedFor() public view {
        uint256 held;
        for (uint256 i; i < 4; ++i) {
            held += token.balanceOf(handler.holder(i));
        }
        assertEq(held, SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(token)), 0);
    }
}
