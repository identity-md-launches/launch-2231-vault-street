// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {VaultStreet} from "../src/VaultStreet.sol";

/// @dev Deploys the token and performs the launch's transfers within a single call, as the factory
/// does in one transaction.
contract LaunchInOneCall {
    function launch(address distributor, address pool, address requester)
        external
        returns (VaultStreet token, uint256 swarm, uint256 seeded, uint256 rest)
    {
        token = new VaultStreet();
        uint256 supply = token.totalSupply();
        swarm = supply * 1_000 / 10_000;
        seeded = supply * 6_000 / 10_000;
        rest = supply - swarm - seeded;
        require(token.transfer(distributor, swarm));
        require(token.transfer(pool, seeded));
        require(token.transfer(requester, rest));
    }
}

/// @dev Edge cases at the extremes of the ERC-20 surface the existing suite does not pin.
contract VaultStreetEdgeTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 1e18;

    VaultStreet private token;
    address private deployer = makeAddr("edge deployer");
    address private alice = makeAddr("edge alice");
    address private bob = makeAddr("edge bob");

    function setUp() public {
        vm.prank(deployer);
        token = new VaultStreet();
    }

    function test_supplyConstantMatchesBrief() public view {
        assertEq(SUPPLY, 1e27);
        assertEq(token.totalSupply(), 1_000_000_000 * 10 ** uint256(token.decimals()));
    }

    function test_launchInOneTransactionDeliversExactAmounts() public {
        LaunchInOneCall factory = new LaunchInOneCall();
        address distributor = makeAddr("distributor");
        address pool = makeAddr("pool");
        address requester = makeAddr("requester");
        (VaultStreet t, uint256 swarm, uint256 seeded, uint256 rest) = factory.launch(distributor, pool, requester);
        assertEq(t.balanceOf(distributor), swarm);
        assertEq(t.balanceOf(pool), seeded);
        assertEq(t.balanceOf(requester), rest);
        assertEq(t.balanceOf(address(factory)), 0);
        assertEq(swarm + seeded + rest, SUPPLY);
        assertEq(t.totalSupply(), SUPPLY);
    }

    function test_eachDeploymentIsIndependentAndMintsOnlyOnce() public {
        vm.prank(alice);
        VaultStreet second = new VaultStreet();
        assertEq(second.balanceOf(alice), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(second.totalSupply(), SUPPLY);
    }

    function test_transferOfOneMoreThanBalanceReverts() public {
        vm.prank(deployer);
        token.transfer(alice, 5);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 5, 6));
        vm.prank(alice);
        token.transfer(bob, 6);
        assertEq(token.balanceOf(alice), 5);
        assertEq(token.balanceOf(bob), 0);
    }

    function test_transferMaxUintRevertsWithoutOverflow() public {
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, deployer, SUPPLY, type(uint256).max)
        );
        vm.prank(deployer);
        token.transfer(alice, type(uint256).max);
    }

    function test_maxApprovalIsNotEnoughToOverdrawBalance() public {
        vm.prank(alice);
        token.approve(bob, type(uint256).max);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 0, 1));
        vm.prank(bob);
        token.transferFrom(alice, bob, 1);
        assertEq(token.allowance(alice, bob), type(uint256).max);
    }

    function test_tokenAddressCanReceiveAndSendItsOwnToken() public {
        vm.prank(deployer);
        token.transfer(address(token), 7);
        assertEq(token.balanceOf(address(token)), 7);
        vm.prank(address(token));
        token.transfer(alice, 7);
        assertEq(token.balanceOf(alice), 7);
        assertEq(token.balanceOf(address(token)), 0);
    }

    function test_spendingFiniteAllowanceEmitsNoApprovalEvent() public {
        vm.prank(deployer);
        token.approve(alice, 10);
        vm.recordLogs();
        vm.prank(alice);
        token.transferFrom(deployer, bob, 4);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1, "only the Transfer event is emitted");
        assertEq(logs[0].topics[0], keccak256("Transfer(address,address,uint256)"));
        assertEq(token.allowance(deployer, alice), 6);
    }

    function test_unknownSelectorAndCalldataRevert() public {
        (bool ok,) = address(token).call(hex"deadbeef");
        assertFalse(ok);
        (ok,) = address(token)
            .call(
                abi.encodeWithSignature(
                    "permit(address,address,uint256,uint256,uint8,bytes32,bytes32)",
                    alice,
                    bob,
                    1,
                    1,
                    27,
                    bytes32(0),
                    bytes32(0)
                )
            );
        assertFalse(ok);
        (ok,) = address(token).call(abi.encodeWithSignature("increaseAllowance(address,uint256)", bob, 1));
        assertFalse(ok);
        assertEq(token.allowance(address(this), bob), 0);
    }

    function test_approveDoesNotAcceptEther() public {
        vm.deal(alice, 1 ether);
        vm.prank(alice);
        (bool ok,) = address(token).call{value: 1}(abi.encodeCall(token.approve, (bob, 1)));
        assertFalse(ok, "non-payable approve accepted ether");
        assertEq(token.allowance(alice, bob), 0);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_chainOfTransfersConservesSupply(uint256 a, uint256 b, uint256 c) public {
        a = bound(a, 0, SUPPLY);
        vm.prank(deployer);
        token.transfer(alice, a);
        b = bound(b, 0, a);
        vm.prank(alice);
        token.transfer(bob, b);
        c = bound(c, 0, b);
        vm.prank(bob);
        token.transfer(deployer, c);
        assertEq(token.balanceOf(deployer), SUPPLY - a + c);
        assertEq(token.balanceOf(alice), a - b);
        assertEq(token.balanceOf(bob), b - c);
        assertEq(token.balanceOf(deployer) + token.balanceOf(alice) + token.balanceOf(bob), SUPPLY);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_approveSetsExactValueRegardlessOfPrevious(uint256 first, uint256 second) public {
        vm.startPrank(alice);
        token.approve(bob, first);
        token.approve(bob, second);
        vm.stopPrank();
        assertEq(token.allowance(alice, bob), second);
        assertEq(token.allowance(bob, alice), 0);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_strangerCannotPullFromHolder(address stranger, uint256 amount) public {
        vm.assume(stranger != deployer);
        amount = bound(amount, 1, SUPPLY);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, stranger, 0, amount));
        vm.prank(stranger);
        token.transferFrom(deployer, stranger, amount);
        assertEq(token.balanceOf(deployer), SUPPLY);
    }
}
