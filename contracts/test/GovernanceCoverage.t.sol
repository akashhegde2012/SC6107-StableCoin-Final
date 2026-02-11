// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {MockV3Aggregator} from "chainlink-brownie-contracts/contracts/src/v0.8/tests/MockV3Aggregator.sol";

import {StableCoin} from "../src/StableCoin.sol";
import {StableCoinEngine} from "../src/StableCoinEngine.sol";
import {PSM} from "../src/PSM.sol";
import {LiquidationAuction} from "../src/LiquidationAuction.sol";

contract GovernanceCoverageTest is Test {
    uint8 private constant FEED_DECIMALS = 8;
    int256 private constant WETH_PRICE = 2_000e8;
    int256 private constant SC_PRICE = 1e8;

    address private constant ADMIN = address(0xAD);
    address private constant USER = address(0x1);
    address private constant TREASURY = address(0x74);

    StableCoin private s_stableCoin;
    StableCoinEngine private s_engine;
    PSM private s_psm;
    LiquidationAuction private s_liquidationAuction;

    ERC20Mock private s_weth;
    ERC20Mock private s_usdc;
    MockV3Aggregator private s_wethUsdFeed;
    MockV3Aggregator private s_usdcUsdFeed;
    MockV3Aggregator private s_scUsdFeed;

    function setUp() public {
        vm.startPrank(ADMIN);
        s_stableCoin = new StableCoin();
        s_weth = new ERC20Mock();
        s_usdc = new ERC20Mock();
        s_wethUsdFeed = new MockV3Aggregator(FEED_DECIMALS, WETH_PRICE);
        s_usdcUsdFeed = new MockV3Aggregator(FEED_DECIMALS, SC_PRICE);
        s_scUsdFeed = new MockV3Aggregator(FEED_DECIMALS, SC_PRICE);

        address[] memory engineCollateralTokens = new address[](1);
        engineCollateralTokens[0] = address(s_weth);

        address[] memory enginePriceFeeds = new address[](1);
        enginePriceFeeds[0] = address(s_wethUsdFeed);

        s_engine = new StableCoinEngine(engineCollateralTokens, enginePriceFeeds, address(s_stableCoin), address(s_scUsdFeed));
        s_liquidationAuction = new LiquidationAuction(address(s_stableCoin), address(s_engine));
        s_engine.setLiquidationAuction(address(s_liquidationAuction));

        address[] memory psmCollateralTokens = new address[](1);
        psmCollateralTokens[0] = address(s_usdc);

        address[] memory psmPriceFeeds = new address[](1);
        psmPriceFeeds[0] = address(s_usdcUsdFeed);

        uint16[] memory feeBps = new uint16[](1);
        feeBps[0] = 30;

        s_psm = new PSM(address(s_stableCoin), psmCollateralTokens, psmPriceFeeds, feeBps);

        s_stableCoin.grantRole(s_stableCoin.MINTER_ROLE(), address(s_engine));
        s_stableCoin.grantRole(s_stableCoin.BURNER_ROLE(), address(s_engine));
        s_stableCoin.grantRole(s_stableCoin.MINTER_ROLE(), address(s_psm));
        s_stableCoin.grantRole(s_stableCoin.BURNER_ROLE(), address(s_psm));
        vm.stopPrank();
    }

    // --- StableCoinEngine Governance ---

    function testEnginePauseUnpause() public {
        vm.startPrank(ADMIN);
        s_engine.pause();
        assertTrue(s_engine.paused());
        s_engine.unpause();
        assertFalse(s_engine.paused());
        vm.stopPrank();
    }

    function testEnginePauseOnlyAdmin() public {
        vm.prank(USER);
        vm.expectRevert(StableCoinEngine.StableCoinEngine__Unauthorized.selector);
        s_engine.pause();
    }

    function testEngineSetLiquidationThreshold() public {
        vm.prank(ADMIN);
        s_engine.setLiquidationThreshold(60);
        assertEq(s_engine.getLiquidationThreshold(), 60);
    }

    function testEngineSetLiquidationThresholdOnlyAdmin() public {
        vm.prank(USER);
        vm.expectRevert(StableCoinEngine.StableCoinEngine__Unauthorized.selector);
        s_engine.setLiquidationThreshold(60);
    }

    function testEngineSetLiquidationBonus() public {
        vm.prank(ADMIN);
        s_engine.setLiquidationBonus(15);
        assertEq(s_engine.getLiquidationBonus(), 15);
    }

    function testEngineSetLiquidationBonusOnlyAdmin() public {
        vm.prank(USER);
        vm.expectRevert(StableCoinEngine.StableCoinEngine__Unauthorized.selector);
        s_engine.setLiquidationBonus(15);
    }

    function testEngineSetStabilityFeeSensitivity() public {
        vm.prank(ADMIN);
        s_engine.setStabilityFeeSensitivity(5, 4);
        // No getter for sensitivity, but we can check if it doesn't revert
    }

    function testEngineSetStabilityFeeSensitivityOnlyAdmin() public {
        vm.prank(USER);
        vm.expectRevert(StableCoinEngine.StableCoinEngine__Unauthorized.selector);
        s_engine.setStabilityFeeSensitivity(5, 4);
    }

    function testEngineSetStabilityFeeCaps() public {
        vm.prank(ADMIN);
        s_engine.setStabilityFeeCaps(10, 3000);
        assertEq(s_engine.getMinStabilityFeeBps(), 10);
        assertEq(s_engine.getMaxStabilityFeeBps(), 3000);
    }

    function testEngineSetStabilityFeeCapsOnlyAdmin() public {
        vm.prank(USER);
        vm.expectRevert(StableCoinEngine.StableCoinEngine__Unauthorized.selector);
        s_engine.setStabilityFeeCaps(10, 3000);
    }

    function testEngineSetBaseStabilityFee() public {
        vm.prank(ADMIN);
        s_engine.setBaseStabilityFee(300);
        assertEq(s_engine.getBaseStabilityFeeBps(), 300);
    }

    function testEngineSetBaseStabilityFeeOnlyAdmin() public {
        vm.prank(USER);
        vm.expectRevert(StableCoinEngine.StableCoinEngine__Unauthorized.selector);
        s_engine.setBaseStabilityFee(300);
    }

    function testEngineSetLiquidationAuctionOnlyAdmin() public {
        vm.prank(USER);
        vm.expectRevert(StableCoinEngine.StableCoinEngine__Unauthorized.selector);
        s_engine.setLiquidationAuction(address(0x123));
    }

    function testEngineSetLiquidationAuctionRevertsOnZeroAddress() public {
        vm.prank(ADMIN);
        vm.expectRevert(StableCoinEngine.StableCoinEngine__ZeroAddress.selector);
        s_engine.setLiquidationAuction(address(0));
    }

    function testEngineSetLiquidationAuctionRevertsIfAlreadySet() public {
        vm.prank(ADMIN);
        vm.expectRevert(StableCoinEngine.StableCoinEngine__LiquidationAuctionAlreadyConfigured.selector);
        s_engine.setLiquidationAuction(address(0x123));
    }

    // --- StableCoinEngine Pausable ---

    function testEngineFunctionsRevertWhenPaused() public {
        vm.prank(ADMIN);
        s_engine.pause();

        vm.startPrank(USER);
        vm.expectRevert(abi.encodeWithSignature("EnforcedPause()"));
        s_engine.depositCollateral(address(s_weth), 1 ether);

        vm.expectRevert(abi.encodeWithSignature("EnforcedPause()"));
        s_engine.redeemCollateral(address(s_weth), 1 ether);

        vm.expectRevert(abi.encodeWithSignature("EnforcedPause()"));
        s_engine.mintStableCoin(100e18);

        vm.expectRevert(abi.encodeWithSignature("EnforcedPause()"));
        s_engine.burnStableCoin(100e18);

        vm.expectRevert(abi.encodeWithSignature("EnforcedPause()"));
        s_engine.liquidate(address(s_weth), USER, 100e18);
        vm.stopPrank();
    }

    // --- PSM Governance ---

    function testPsmPauseUnpause() public {
        vm.startPrank(ADMIN);
        s_psm.pause();
        assertTrue(s_psm.paused());
        s_psm.unpause();
        assertFalse(s_psm.paused());
        vm.stopPrank();
    }

    function testPsmPauseOnlyAdmin() public {
        vm.prank(USER);
        vm.expectRevert(PSM.PSM__Unauthorized.selector);
        s_psm.pause();
    }

    function testPsmSetPegBounds() public {
        vm.prank(ADMIN);
        s_psm.setPegBounds(98e16, 102e16);
        (uint256 lower, uint256 upper) = s_psm.getPegBounds();
        assertEq(lower, 98e16);
        assertEq(upper, 102e16);
    }

    function testPsmSetPegBoundsOnlyAdmin() public {
        vm.prank(USER);
        vm.expectRevert(PSM.PSM__Unauthorized.selector);
        s_psm.setPegBounds(98e16, 102e16);
    }

    function testPsmSetTokenFeeBps() public {
        vm.prank(ADMIN);
        s_psm.setTokenFeeBps(address(s_usdc), 50);
        assertEq(s_psm.getTokenConfig(address(s_usdc)).feeBps, 50);
    }

    function testPsmSetTokenFeeBpsOnlyAdmin() public {
        vm.prank(USER);
        vm.expectRevert(PSM.PSM__Unauthorized.selector);
        s_psm.setTokenFeeBps(address(s_usdc), 50);
    }

    function testPsmSetTokenFeeBpsRevertsOnTooHigh() public {
        vm.prank(ADMIN);
        vm.expectRevert(abi.encodeWithSelector(PSM.PSM__FeeTooHigh.selector, 10001));
        s_psm.setTokenFeeBps(address(s_usdc), 10001);
    }

    function testPsmSetTreasury() public {
        vm.prank(ADMIN);
        s_psm.setTreasury(TREASURY);
        assertEq(s_psm.getTreasury(), TREASURY);
    }

    function testPsmSetTreasuryOnlyAdmin() public {
        vm.prank(USER);
        vm.expectRevert(PSM.PSM__Unauthorized.selector);
        s_psm.setTreasury(TREASURY);
    }

    function testPsmSetTreasuryRevertsOnZeroAddress() public {
        vm.prank(ADMIN);
        vm.expectRevert(PSM.PSM__ZeroAddress.selector);
        s_psm.setTreasury(address(0));
    }

    function testPsmCollectFees() public {
        // Setup some fees
        uint256 amount = 1000e18;
        s_usdc.mint(USER, amount);
        vm.startPrank(USER);
        s_usdc.approve(address(s_psm), amount);
        s_psm.swapStableForStableCoin(address(s_usdc), amount);
        vm.stopPrank();

        uint256 fees = s_psm.getAccumulatedFees(address(s_usdc));
        assertGt(fees, 0);

        vm.startPrank(ADMIN);
        s_psm.setTreasury(TREASURY);
        s_psm.collectFees(address(s_usdc));
        vm.stopPrank();

        assertEq(s_psm.getAccumulatedFees(address(s_usdc)), 0);
        assertEq(s_usdc.balanceOf(TREASURY), fees);
    }

    function testPsmCollectFeesOnlyAdmin() public {
        vm.prank(USER);
        vm.expectRevert(PSM.PSM__Unauthorized.selector);
        s_psm.collectFees(address(s_usdc));
    }

    function testPsmCollectFeesRevertsOnNoFees() public {
        vm.prank(ADMIN);
        vm.expectRevert(PSM.PSM__NoFeesToCollect.selector);
        s_psm.collectFees(address(s_usdc));
    }

    function testPsmCollectFeesRevertsOnZeroTreasury() public {
        // Setup some fees
        uint256 amount = 1000e18;
        s_usdc.mint(USER, amount);
        vm.startPrank(USER);
        s_usdc.approve(address(s_psm), amount);
        s_psm.swapStableForStableCoin(address(s_usdc), amount);
        vm.stopPrank();

        vm.prank(ADMIN);
        vm.expectRevert(PSM.PSM__ZeroAddress.selector);
        s_psm.collectFees(address(s_usdc));
    }

    // --- PSM Pausable ---

    function testPsmFunctionsRevertWhenPaused() public {
        vm.prank(ADMIN);
        s_psm.pause();

        vm.startPrank(USER);
        vm.expectRevert(abi.encodeWithSignature("EnforcedPause()"));
        s_psm.swapStableForStableCoin(address(s_usdc), 1 ether);

        vm.expectRevert(abi.encodeWithSignature("EnforcedPause()"));
        s_psm.swapStableCoinForStable(address(s_usdc), 1 ether);
        vm.stopPrank();
    }
}
