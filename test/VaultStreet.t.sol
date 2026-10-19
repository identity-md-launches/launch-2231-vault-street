// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {VaultStreet} from "../src/VaultStreet.sol";

/// @dev Local deployment/transfer harness; never a launch deployment artifact.
contract TokenFactoryHarness {
    function deploy(bytes32 salt) external returns (VaultStreet) {
        return new VaultStreet{salt: salt}();
    }

    function move(VaultStreet token, address recipient, uint256 amount) external returns (bool) {
        return token.transfer(recipient, amount);
    }
}

contract VaultStreetTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000_000_000_000_000_000_000;

    VaultStreet private token;
    address private deployer;
    address private alice;
    address private bob;
    address private spender;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function setUp() public {
        deployer = makeAddr("deployer");
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        spender = makeAddr("spender");
        vm.prank(deployer);
        token = new VaultStreet();
    }

    function test_metadataAndEntireInitialSupply() public view {
        assertEq(token.name(), "Vault Street");
        assertEq(token.symbol(), "VST");
        assertEq(token.decimals(), 18);
        assertEq(token.INITIAL_SUPPLY(), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.allowance(deployer, spender), 0);
    }

    function test_constructorEmitsMintTransfer() public {
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(0), alice, SUPPLY);
        vm.prank(alice);
        VaultStreet deployed = new VaultStreet();
        assertEq(deployed.balanceOf(alice), SUPPLY);
    }

    function test_create2DeploymentMintsToFactoryInsteadOfTransactionOrigin() public {
        TokenFactoryHarness factory = new TokenFactoryHarness();
        bytes32 salt = keccak256("VST deployment test");
        address predicted = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            bytes1(0xff), address(factory), salt, keccak256(type(VaultStreet).creationCode)
                        )
                    )
                )
            )
        );

        vm.prank(alice, alice);
        VaultStreet deployed = factory.deploy(salt);
        assertEq(address(deployed), predicted);
        assertEq(deployed.totalSupply(), SUPPLY);
        assertEq(deployed.balanceOf(address(factory)), SUPPLY);
        assertEq(deployed.balanceOf(alice), 0);
        assertEq(deployed.balanceOf(address(this)), 0);
    }

    function test_factoryDistributionClaimsAndPoolTransfersDeliverExactAmounts() public {
        TokenFactoryHarness factory = new TokenFactoryHarness();
        VaultStreet deployed = factory.deploy(keccak256("distribution test"));
        address distributor = makeAddr("distributor");
        address poolManager = makeAddr("pool manager actor");
        address requester = makeAddr("requester");
        uint256 swarm = SUPPLY / 10;
        uint256 pool = SUPPLY * 8 / 10;

        assertTrue(factory.move(deployed, distributor, swarm));
        assertTrue(factory.move(deployed, poolManager, pool));
        assertTrue(factory.move(deployed, requester, SUPPLY - swarm - pool));
        assertEq(deployed.balanceOf(address(factory)), 0);
        assertEq(deployed.balanceOf(distributor), swarm);
        assertEq(deployed.balanceOf(poolManager), pool);
        assertEq(deployed.balanceOf(requester), SUPPLY / 10);

        vm.prank(distributor);
        assertTrue(deployed.transfer(alice, swarm));
        assertEq(deployed.balanceOf(distributor), 0);
        assertEq(deployed.balanceOf(alice), swarm);

        // These exercise the token side of pool transfers, not a real AMM swap.
        vm.prank(poolManager);
        assertTrue(deployed.transfer(bob, 17 ether));
        assertEq(deployed.balanceOf(bob), 17 ether);
        vm.prank(bob);
        assertTrue(deployed.transfer(poolManager, 17 ether));
        assertEq(deployed.balanceOf(bob), 0);
        assertEq(deployed.balanceOf(poolManager), pool);
        assertEq(deployed.totalSupply(), SUPPLY);
    }

    function test_transferReturnsTrueEmitsEventAndMovesExactAmount() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(deployer, alice, 42 ether);
        vm.prank(deployer);
        assertTrue(token.transfer(alice, 42 ether));
        assertEq(token.balanceOf(deployer), SUPPLY - 42 ether);
        assertEq(token.balanceOf(alice), 42 ether);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_transferEntireBalance() public {
        vm.prank(deployer);
        assertTrue(token.transfer(alice, SUPPLY));
        assertEq(token.balanceOf(deployer), 0);
        assertEq(token.balanceOf(alice), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_zeroTransferFromEmptyAccountEmitsEvent() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(alice, bob, 0);
        vm.prank(alice);
        assertTrue(token.transfer(bob, 0));
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_selfTransferDoesNotChangeBalance() public {
        vm.prank(deployer);
        assertTrue(token.transfer(deployer, SUPPLY));
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_transferToZeroReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(deployer);
        token.transfer(address(0), 1);
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_zeroTransferToZeroReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(deployer);
        token.transfer(address(0), 0);
    }

    function test_transferFromEmptyAccountReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 0, 1));
        vm.prank(alice);
        token.transfer(bob, 1);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
    }

    function test_selfTransferStillRequiresSufficientBalance() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 0, 1));
        vm.prank(alice);
        token.transfer(alice, 1);
    }

    function test_approveEmitsEventAndCanReplaceOrRevokeAllowance() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Approval(deployer, spender, 100 ether);
        vm.startPrank(deployer);
        assertTrue(token.approve(spender, 100 ether));
        assertEq(token.allowance(deployer, spender), 100 ether);
        assertTrue(token.approve(spender, 25 ether));
        assertEq(token.allowance(deployer, spender), 25 ether);
        assertTrue(token.approve(spender, 0));
        vm.stopPrank();
        assertEq(token.allowance(deployer, spender), 0);
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_approveDoesNotRequireTokenBalance() public {
        vm.prank(alice);
        assertTrue(token.approve(spender, type(uint256).max));
        assertEq(token.allowance(alice, spender), type(uint256).max);
        assertEq(token.balanceOf(alice), 0);
    }

    function test_approveZeroSpenderReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        vm.prank(deployer);
        token.approve(address(0), 1);
        assertEq(token.allowance(deployer, address(0)), 0);
    }

    function test_transferFromEmitsTransferAndConsumesFiniteAllowance() public {
        vm.prank(deployer);
        token.approve(spender, 100 ether);
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(deployer, alice, 40 ether);
        vm.prank(spender);
        assertTrue(token.transferFrom(deployer, alice, 40 ether));
        assertEq(token.allowance(deployer, spender), 60 ether);
        assertEq(token.balanceOf(deployer), SUPPLY - 40 ether);
        assertEq(token.balanceOf(alice), 40 ether);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_transferFromCanSpendExactAllowanceOnlyOnce() public {
        vm.prank(deployer);
        token.approve(spender, 20 ether);
        vm.prank(spender);
        assertTrue(token.transferFrom(deployer, alice, 20 ether));
        assertEq(token.allowance(deployer, spender), 0);

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(deployer, bob, 1);
        assertEq(token.balanceOf(alice), 20 ether);
        assertEq(token.balanceOf(bob), 0);
    }

    function test_transferFromInfiniteApprovalRemainsInfinite() public {
        vm.prank(deployer);
        token.approve(spender, type(uint256).max);
        vm.startPrank(spender);
        assertTrue(token.transferFrom(deployer, alice, 1));
        assertTrue(token.transferFrom(deployer, bob, SUPPLY - 1));
        vm.stopPrank();
        assertEq(token.allowance(deployer, spender), type(uint256).max);
        assertEq(token.balanceOf(deployer), 0);
        assertEq(token.balanceOf(alice), 1);
        assertEq(token.balanceOf(bob), SUPPLY - 1);
    }

    function test_transferFromWithoutApprovalReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(deployer, alice, 1);
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
    }

    function test_revokedApprovalCannotBeSpent() public {
        vm.startPrank(deployer);
        token.approve(spender, 10 ether);
        token.approve(spender, 0);
        vm.stopPrank();
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(deployer, alice, 1);
        assertEq(token.balanceOf(deployer), SUPPLY);
    }

    function test_approvalIsScopedToOwnerAndSpender() public {
        vm.prank(deployer);
        token.approve(spender, 10 ether);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, bob, 0, 1));
        vm.prank(bob);
        token.transferFrom(deployer, alice, 1);

        vm.prank(deployer);
        token.transfer(alice, 10 ether);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(alice, bob, 1);
        assertEq(token.allowance(deployer, spender), 10 ether);
        assertEq(token.balanceOf(alice), 10 ether);
        assertEq(token.balanceOf(bob), 0);
    }

    function test_deployerCannotMoveHolderBalanceWithoutApproval() public {
        vm.prank(deployer);
        token.transfer(alice, 10 ether);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, deployer, 0, 1));
        vm.prank(deployer);
        token.transferFrom(alice, deployer, 1);
        assertEq(token.balanceOf(alice), 10 ether);
    }

    function test_transferFromToZeroRevertsAndPreservesAllowance() public {
        vm.prank(deployer);
        token.approve(spender, 10 ether);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(deployer, address(0), 10 ether);
        assertEq(token.allowance(deployer, spender), 10 ether);
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_zeroTransferFromZeroSenderReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidApprover.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(address(0), alice, 0);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_zeroTransferFromRequiresNoAllowanceForValidAddresses() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(alice, bob, 0);
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, 0));
        assertEq(token.allowance(alice, spender), 0);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
    }

    function test_transferFromToSameHolderConsumesAllowanceWithoutChangingBalance() public {
        vm.prank(deployer);
        token.approve(spender, 10 ether);
        vm.prank(spender);
        assertTrue(token.transferFrom(deployer, deployer, 10 ether));
        assertEq(token.allowance(deployer, spender), 0);
        assertEq(token.balanceOf(deployer), SUPPLY);
    }

    function test_noMintBurnAdministrationOrUpgradeEntryPoints() public {
        vm.prank(deployer);
        token.transfer(alice, 10 ether);

        bytes[] memory calls = new bytes[](16);
        calls[0] = abi.encodeWithSignature("mint(address,uint256)", bob, 1 ether);
        calls[1] = abi.encodeWithSignature("mint(uint256)", 1 ether);
        calls[2] = abi.encodeWithSignature("mint()");
        calls[3] = abi.encodeWithSignature("burn(uint256)", 1 ether);
        calls[4] = abi.encodeWithSignature("burnFrom(address,uint256)", alice, 1 ether);
        calls[5] = abi.encodeWithSignature("pause()");
        calls[6] = abi.encodeWithSignature("blacklist(address)", alice);
        calls[7] = abi.encodeWithSignature("freeze(address)", alice);
        calls[8] = abi.encodeWithSignature("seize(address)", alice);
        calls[9] = abi.encodeWithSignature("initialize(address)", bob);
        calls[10] = abi.encodeWithSignature("transferOwnership(address)", bob);
        calls[11] = abi.encodeWithSignature("setMinter(address)", bob);
        calls[12] = abi.encodeWithSignature("upgradeTo(address)", bob);
        calls[13] = abi.encodeWithSignature("_mint(address,uint256)", bob, 1 ether);
        calls[14] = abi.encodeWithSignature("_burn(address,uint256)", alice, 1 ether);
        calls[15] = abi.encodeWithSignature("owner()");

        for (uint256 i; i < calls.length; ++i) {
            vm.prank(deployer);
            (bool deployerSucceeded,) = address(token).call(calls[i]);
            assertFalse(deployerSucceeded, "deployer reached an unintended entry point");
            vm.prank(bob);
            (bool strangerSucceeded,) = address(token).call(calls[i]);
            assertFalse(strangerSucceeded, "stranger reached an unintended entry point");
        }
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(alice), 10 ether);
        assertEq(token.balanceOf(bob), 0);
        vm.prank(alice);
        assertTrue(token.transfer(bob, 10 ether));
        assertEq(token.balanceOf(bob), 10 ether);
    }

    function test_nativeEtherTransferReverts() public {
        vm.deal(alice, 1 ether);
        vm.prank(alice);
        (bool success,) = address(token).call{value: 1 ether}("");
        assertFalse(success);
        assertEq(address(token).balance, 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_runtimeHasNoForbiddenOpcodesAndFitsDeploymentLimit() public view {
        bytes memory runtime = address(token).code;
        assertGt(runtime.length, 0);
        assertLe(runtime.length, 24_576);
        for (uint256 i; i < runtime.length; ++i) {
            uint8 opcode = uint8(runtime[i]);
            if (opcode >= 0x60 && opcode <= 0x7f) {
                i += opcode - 0x5f;
                continue;
            }
            assertTrue(opcode != 0xf4 && opcode != 0xf2 && opcode != 0xff, "forbidden opcode");
        }
    }

    function testFuzz_transferConservesSupply(address recipient, uint256 amount) public {
        vm.assume(recipient != address(0));
        amount = bound(amount, 0, SUPPLY);
        vm.prank(deployer);
        assertTrue(token.transfer(recipient, amount));
        if (recipient == deployer) {
            assertEq(token.balanceOf(deployer), SUPPLY);
        } else {
            assertEq(token.balanceOf(deployer), SUPPLY - amount);
            assertEq(token.balanceOf(recipient), amount);
        }
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
    }

    function testFuzz_transferAboveBalanceReverts(uint256 amount) public {
        amount = bound(amount, SUPPLY + 1, type(uint256).max);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, deployer, SUPPLY, amount)
        );
        vm.prank(deployer);
        token.transfer(alice, amount);
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
    }

    function testFuzz_approvedTransferAccountsForAllowanceAndBalances(uint256 approved, uint256 spent) public {
        approved = bound(approved, 0, SUPPLY);
        spent = bound(spent, 0, approved);
        vm.prank(deployer);
        token.approve(spender, approved);
        vm.prank(spender);
        assertTrue(token.transferFrom(deployer, alice, spent));
        assertEq(token.allowance(deployer, spender), approved - spent);
        assertEq(token.balanceOf(deployer), SUPPLY - spent);
        assertEq(token.balanceOf(alice), spent);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_transferAboveAllowanceReverts(uint256 approved, uint256 attempted) public {
        approved = bound(approved, 0, SUPPLY - 1);
        attempted = bound(attempted, approved + 1, SUPPLY);
        vm.prank(deployer);
        token.approve(spender, approved);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, approved, attempted)
        );
        vm.prank(spender);
        token.transferFrom(deployer, alice, attempted);
        assertEq(token.allowance(deployer, spender), approved);
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
    }

    function testFuzz_failedTransferFromPreservesAllowance(uint256 balance, uint256 attempted) public {
        balance = bound(balance, 0, SUPPLY - 1);
        attempted = bound(attempted, balance + 1, SUPPLY);
        vm.prank(deployer);
        token.transfer(alice, balance);
        vm.prank(alice);
        token.approve(spender, attempted);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, balance, attempted)
        );
        vm.prank(spender);
        token.transferFrom(alice, bob, attempted);
        assertEq(token.allowance(alice, spender), attempted);
        assertEq(token.balanceOf(alice), balance);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }
}
