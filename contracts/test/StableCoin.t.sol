// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {StableCoin} from "../src/StableCoin.sol";

contract StableCoinTest is Test {
    StableCoin public stableCoin;
    address public admin;
    address public minter;
    address public burner;
    address public user;

    bytes32 public minterRole;
    bytes32 public burnerRole;

    function setUp() public {
        admin = makeAddr("admin");
        minter = makeAddr("minter");
        burner = makeAddr("burner");
        user = makeAddr("user");

        vm.startPrank(admin);
        stableCoin = new StableCoin();
        minterRole = stableCoin.MINTER_ROLE();
        burnerRole = stableCoin.BURNER_ROLE();
        stableCoin.grantRole(minterRole, minter);
        stableCoin.grantRole(burnerRole, burner);
        vm.stopPrank();
    }

    // Mint Tests
    function testMintSuccess() public {
        vm.prank(minter);
        stableCoin.mint(user, 100);
        assertEq(stableCoin.balanceOf(user), 100);
    }

    function testMintRevertNotMinter() public {
        vm.prank(user);
        vm.expectRevert();
        stableCoin.mint(user, 100);
    }

    function testMintRevertZeroAddress() public {
        vm.prank(minter);
        vm.expectRevert(StableCoin.StableCoin__NotZeroAddress.selector);
        stableCoin.mint(address(0), 100);
    }

    function testMintRevertZeroAmount() public {
        vm.prank(minter);
        vm.expectRevert(StableCoin.StableCoin__AmountMustBeMoreThanZero.selector);
        stableCoin.mint(user, 0);
    }

    // Burn Tests
    function testBurnSuccess() public {
        vm.prank(minter);
        stableCoin.mint(user, 100);

        vm.prank(burner);
        stableCoin.burn(user, 50);
        assertEq(stableCoin.balanceOf(user), 50);
    }

    function testBurnRevertNotBurner() public {
        vm.prank(minter);
        stableCoin.mint(user, 100);

        vm.prank(user);
        vm.expectRevert();
        stableCoin.burn(user, 50);
    }

    function testBurnRevertZeroAmount() public {
        vm.prank(burner);
        vm.expectRevert(StableCoin.StableCoin__AmountMustBeMoreThanZero.selector);
        stableCoin.burn(user, 0);
    }

    function testBurnRevertExceedsBalance() public {
        vm.prank(minter);
        stableCoin.mint(user, 100);

        vm.prank(burner);
        vm.expectRevert(StableCoin.StableCoin__BurnAmountExceedsBalance.selector);
        stableCoin.burn(user, 101);
    }

    // AccessControl Tests
    function testAdminCanGrantRoles() public {
        vm.prank(admin);
        stableCoin.grantRole(minterRole, user);
        assertTrue(stableCoin.hasRole(minterRole, user));
    }

    function testNonAdminCannotGrantRoles() public {
        vm.prank(user);
        vm.expectRevert();
        stableCoin.grantRole(minterRole, user);
    }
}
