// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {MockV3Aggregator} from "chainlink-brownie-contracts/contracts/src/v0.8/tests/MockV3Aggregator.sol";

import {StableCoin} from "../src/StableCoin.sol";
import {StableCoinEngine} from "../src/StableCoinEngine.sol";
import {LiquidationAuction} from "../src/LiquidationAuction.sol";

contract StableCoinEngineTest is Test {
    uint8 private constant FEED_DECIMALS = 8;
    int256 private constant WETH_PRICE = 2_000e8;
    int256 private constant WBTC_PRICE = 30_000e8;
    int256 private constant SC_PRICE = 1e8;

    address private constant USER = address(1);
    address private constant LIQUIDATOR = address(2);
    address private constant BAD_TOKEN = address(3);

    StableCoin private s_stableCoin;
    StableCoinEngine private s_engine;
    LiquidationAuction private s_liquidationAuction;

    ERC20Mock private s_weth;
    ERC20Mock private s_wbtc;

    MockV3Aggregator private s_wethUsdFeed;
    MockV3Aggregator private s_wbtcUsdFeed;
    MockV3Aggregator private s_scUsdFeed;

    function setUp() public {
        s_stableCoin = new StableCoin();
        s_weth = new ERC20Mock();
        s_wbtc = new ERC20Mock();

        s_wethUsdFeed = new MockV3Aggregator(FEED_DECIMALS, WETH_PRICE);
        s_wbtcUsdFeed = new MockV3Aggregator(FEED_DECIMALS, WBTC_PRICE);
        s_scUsdFeed = new MockV3Aggregator(FEED_DECIMALS, SC_PRICE);

        address[] memory collateralTokens = new address[](2);
        collateralTokens[0] = address(s_weth);
        collateralTokens[1] = address(s_wbtc);

        address[] memory priceFeeds = new address[](2);
        priceFeeds[0] = address(s_wethUsdFeed);
        priceFeeds[1] = address(s_wbtcUsdFeed);

        s_engine = new StableCoinEngine(collateralTokens, priceFeeds, address(s_stableCoin), address(s_scUsdFeed));
        s_liquidationAuction = new LiquidationAuction(address(s_stableCoin), address(s_engine));
        s_engine.setLiquidationAuction(address(s_liquidationAuction));
        s_stableCoin.grantRole(s_stableCoin.MINTER_ROLE(), address(s_engine));
        s_stableCoin.grantRole(s_stableCoin.BURNER_ROLE(), address(s_engine));
    }

    function testDepositCollateralUpdatesStateAndTransfersToken() public {
        uint256 amount = 10 ether;
        _depositCollateral(USER, address(s_weth), amount);

        assertEq(s_engine.getCollateralBalanceOfUser(USER, address(s_weth)), amount);
        assertEq(s_weth.balanceOf(address(s_engine)), amount);
    }

    function testDepositCollateralRevertsOnZeroAmount() public {
        vm.prank(USER);
        vm.expectRevert(StableCoinEngine.StableCoinEngine__AmountMustBeMoreThanZero.selector);
        s_engine.depositCollateral(address(s_weth), 0);
    }

    function testDepositCollateralRevertsForUnsupportedToken() public {
        vm.prank(USER);
        vm.expectRevert(abi.encodeWithSelector(StableCoinEngine.StableCoinEngine__TokenNotAllowed.selector, BAD_TOKEN));
        s_engine.depositCollateral(BAD_TOKEN, 1 ether);
    }

    function testRedeemCollateralSuccessWhenNoDebt() public {
        _depositCollateral(USER, address(s_weth), 10 ether);

        vm.prank(USER);
        s_engine.redeemCollateral(address(s_weth), 4 ether);

        assertEq(s_engine.getCollateralBalanceOfUser(USER, address(s_weth)), 6 ether);
        assertEq(s_weth.balanceOf(USER), 4 ether);
    }

    function testRedeemCollateralRevertsOnZeroAmount() public {
        vm.prank(USER);
        vm.expectRevert(StableCoinEngine.StableCoinEngine__AmountMustBeMoreThanZero.selector);
        s_engine.redeemCollateral(address(s_weth), 0);
    }

    function testRedeemCollateralRevertsForInsufficientCollateral() public {
        _depositCollateral(USER, address(s_weth), 1 ether);

        vm.prank(USER);
        vm.expectRevert(StableCoinEngine.StableCoinEngine__InsufficientCollateral.selector);
        s_engine.redeemCollateral(address(s_weth), 2 ether);
    }

    function testRedeemCollateralRevertsWhenHealthFactorWouldBreak() public {
        _depositCollateral(USER, address(s_weth), 10 ether);

        vm.prank(USER);
        s_engine.mintStableCoin(5_000e18);

        vm.prank(USER);
        vm.expectRevert(
            abi.encodeWithSelector(StableCoinEngine.StableCoinEngine__BreaksHealthFactor.selector, 400000000000000000)
        );
        s_engine.redeemCollateral(address(s_weth), 8 ether);
    }

    function testMintStableCoinSuccess() public {
        _depositCollateral(USER, address(s_weth), 10 ether);

        vm.prank(USER);
        s_engine.mintStableCoin(5_000e18);

        assertEq(s_engine.getStableCoinMinted(USER), 5_000e18);
        assertEq(s_stableCoin.balanceOf(USER), 5_000e18);
    }

    function testMintStableCoinRevertsOnZeroAmount() public {
        vm.prank(USER);
        vm.expectRevert(StableCoinEngine.StableCoinEngine__AmountMustBeMoreThanZero.selector);
        s_engine.mintStableCoin(0);
    }

    function testMintStableCoinRevertsWhenHealthFactorWouldBreak() public {
        _depositCollateral(USER, address(s_weth), 10 ether);

        vm.prank(USER);
        vm.expectRevert(
            abi.encodeWithSelector(
                StableCoinEngine.StableCoinEngine__BreaksHealthFactor.selector, 999900009999000099
            )
        );
        s_engine.mintStableCoin(10_001e18);
    }

    function testBurnStableCoinSuccess() public {
        _depositCollateral(USER, address(s_weth), 10 ether);

        vm.prank(USER);
        s_engine.mintStableCoin(1_000e18);

        vm.prank(USER);
        s_engine.burnStableCoin(400e18);

        assertEq(s_engine.getStableCoinMinted(USER), 600e18);
        assertEq(s_stableCoin.balanceOf(USER), 600e18);
    }

    function testBurnStableCoinRevertsOnZeroAmount() public {
        vm.prank(USER);
        vm.expectRevert(StableCoinEngine.StableCoinEngine__AmountMustBeMoreThanZero.selector);
        s_engine.burnStableCoin(0);
    }

    function testBurnStableCoinRevertsWhenBurnExceedsMinted() public {
        _depositCollateral(USER, address(s_weth), 10 ether);

        vm.prank(USER);
        s_engine.mintStableCoin(500e18);

        vm.prank(USER);
        vm.expectRevert(
            abi.encodeWithSelector(
                StableCoinEngine.StableCoinEngine__BurnAmountExceedsMinted.selector, 501000000000000000000, 500000000000000000000
            )
        );
        s_engine.burnStableCoin(501e18);
    }

    function testLiquidateRevertsWhenHealthFactorIsOk() public {
        _depositCollateral(USER, address(s_weth), 10 ether);

        vm.prank(USER);
        s_engine.mintStableCoin(5_000e18);

        vm.prank(LIQUIDATOR);
        vm.expectRevert(StableCoinEngine.StableCoinEngine__HealthFactorOk.selector);
        s_engine.liquidate(address(s_weth), USER, 1_000e18);
    }

    function testLiquidateCreatesAuctionAndReservesDebt() public {
        _depositCollateral(USER, address(s_weth), 10 ether);
        vm.prank(USER);
        s_engine.mintStableCoin(9_500e18);

        vm.warp(block.timestamp + 31 minutes);
        s_wethUsdFeed.updateAnswer(1_000e8);

        _depositCollateral(LIQUIDATOR, address(s_weth), 10 ether);
        vm.prank(LIQUIDATOR);
        s_engine.mintStableCoin(1_000e18);

        vm.prank(LIQUIDATOR);
        s_engine.liquidate(address(s_weth), USER, 1_000e18);

        (address auctionUser, address auctionToken, uint256 debtToCover, uint256 collateralAmount, bool active) =
            s_engine.getPendingLiquidationAuction(0);

        assertEq(auctionUser, USER);
        assertEq(auctionToken, address(s_weth));
        assertEq(debtToCover, 1_000e18);
        assertEq(collateralAmount, 1.1 ether);
        assertTrue(active);
        assertEq(s_engine.getDebtReservedForAuction(USER), 1_000e18);
        assertTrue(s_engine.hasActiveLiquidationAuction(USER, address(s_weth)));
    }

    function testLiquidateSuccessImprovesHealthFactorAndTransfersBonusCollateral() public {
        _depositCollateral(USER, address(s_weth), 10 ether);
        vm.prank(USER);
        s_engine.mintStableCoin(9_000e18);

        vm.warp(block.timestamp + 31 minutes);
        s_wethUsdFeed.updateAnswer(1_000e8);

        _depositCollateral(LIQUIDATOR, address(s_weth), 10 ether);
        vm.prank(LIQUIDATOR);
        s_engine.mintStableCoin(1_000e18);

        uint256 startingHealthFactor = s_engine.getHealthFactor(USER);
        uint256 debtBeforeLiquidation = s_engine.getStableCoinMinted(USER);

        vm.prank(LIQUIDATOR);
        s_engine.liquidate(address(s_weth), USER, 1_000e18);

        vm.startPrank(LIQUIDATOR);
        s_stableCoin.approve(address(s_liquidationAuction), 1_000e18);
        s_liquidationAuction.placeBid(0, 1_000e18);
        vm.stopPrank();

        s_engine.finalizeLiquidationAuction(0);

        uint256 endingHealthFactor = s_engine.getHealthFactor(USER);
        assertGt(endingHealthFactor, startingHealthFactor);
        assertApproxEqAbs(s_engine.getStableCoinMinted(USER), debtBeforeLiquidation - 1_000e18, 1);
        assertEq(s_weth.balanceOf(LIQUIDATOR), 1.1 ether);
    }

    function testHealthFactorIsMaxWhenNoDebt() public {
        _depositCollateral(USER, address(s_weth), 10 ether);

        assertEq(s_engine.getHealthFactor(USER), type(uint256).max);
    }

    function testHealthFactorMatchesExpectedFormula() public {
        _depositCollateral(USER, address(s_weth), 10 ether);

        vm.prank(USER);
        s_engine.mintStableCoin(5_000e18);

        assertEq(s_engine.getHealthFactor(USER), 2e18);
    }

    function testDynamicStabilityFeeIncreasesDebtWhenBelowPeg() public {
        _depositCollateral(USER, address(s_weth), 10 ether);

        vm.prank(USER);
        s_engine.mintStableCoin(1_000e18);

        s_scUsdFeed.updateAnswer(98e6);
        vm.warp(block.timestamp + 30 days);
        s_scUsdFeed.updateAnswer(98e6);

        s_engine.dripStabilityFee();

        assertGt(s_engine.getStableCoinMinted(USER), 1_000e18);
    }

    function testDynamicStabilityFeeDecreasesWhenAbovePeg() public {
        uint256 baseFee = s_engine.getBaseStabilityFeeBps();

        s_scUsdFeed.updateAnswer(98e6);
        uint256 feeBelowPeg = s_engine.getCurrentStabilityFeeBps();

        s_scUsdFeed.updateAnswer(102e6);
        uint256 feeAbovePeg = s_engine.getCurrentStabilityFeeBps();

        assertGt(feeBelowPeg, baseFee);
        assertLt(feeAbovePeg, baseFee);
    }

    function testAccountCollateralValueSumsAcrossSupportedTokens() public {
        _depositCollateral(USER, address(s_weth), 10 ether);
        _depositCollateral(USER, address(s_wbtc), 1 ether);

        uint256 collateralValue = s_engine.getAccountCollateralValueInUsd(USER);
        assertEq(collateralValue, 50_000e18);
    }

    function _depositCollateral(address user, address token, uint256 amount) internal {
        ERC20Mock(token).mint(user, amount);

        vm.startPrank(user);
        ERC20Mock(token).approve(address(s_engine), amount);
        s_engine.depositCollateral(token, amount);
        vm.stopPrank();
    }
}
