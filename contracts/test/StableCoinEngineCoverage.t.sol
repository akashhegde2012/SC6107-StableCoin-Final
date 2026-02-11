// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, stdStorage, StdStorage} from "forge-std/Test.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {MockV3Aggregator} from "chainlink-brownie-contracts/contracts/src/v0.8/tests/MockV3Aggregator.sol";

import {StableCoin} from "../src/StableCoin.sol";
import {StableCoinEngine} from "../src/StableCoinEngine.sol";
import {LiquidationAuction} from "../src/LiquidationAuction.sol";
import {OracleLib} from "../src/libraries/OracleLib.sol";

contract StableCoinEngineCoverageTest is Test {
    using stdStorage for StdStorage;

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

    function testSetLiquidationAuctionRevertsUnauthorized() public {
        vm.prank(USER);
        vm.expectRevert(StableCoinEngine.StableCoinEngine__Unauthorized.selector);
        s_engine.setLiquidationAuction(address(0x1234));
    }

    function testSetLiquidationAuctionRevertsZeroAddress() public {
        (, StableCoinEngine engine) = _deployEngineWithoutAuction(FEED_DECIMALS, SC_PRICE);

        vm.expectRevert(StableCoinEngine.StableCoinEngine__ZeroAddress.selector);
        engine.setLiquidationAuction(address(0));
    }

    function testSetLiquidationAuctionRevertsAlreadyConfigured() public {
        vm.expectRevert(StableCoinEngine.StableCoinEngine__LiquidationAuctionAlreadyConfigured.selector);
        s_engine.setLiquidationAuction(address(s_liquidationAuction));
    }

    function testBurnStableCoinRevertsDebtReservedForAuction() public {
        _createActiveLiquidationAuction(1_000e18);

        vm.prank(USER);
        vm.expectRevert(
            abi.encodeWithSelector(StableCoinEngine.StableCoinEngine__DebtReservedForAuction.selector, 1_000e18, 9_000e18)
        );
        s_engine.burnStableCoin(9_000e18);
    }

    function testLiquidateRevertsActiveLiquidationAuctionExists() public {
        _createActiveLiquidationAuction(1_000e18);

        vm.prank(LIQUIDATOR);
        vm.expectRevert(
            abi.encodeWithSelector(
                StableCoinEngine.StableCoinEngine__ActiveLiquidationAuctionExists.selector, USER, address(s_weth)
            )
        );
        s_engine.liquidate(address(s_weth), USER, 100e18);
    }

    function testLiquidateRevertsDebtNotAvailableForLiquidation() public {
        _depositCollateral(USER, s_weth, 10 ether);
        _depositCollateral(USER, s_wbtc, 0.01 ether);

        vm.prank(USER);
        s_engine.mintStableCoin(9_500e18);

        vm.warp(block.timestamp + 31 minutes);
        s_wethUsdFeed.updateAnswer(1_000e8);

        vm.prank(LIQUIDATOR);
        s_engine.liquidate(address(s_weth), USER, 9_000e18);

        uint256 availableDebt = s_engine.getStableCoinMinted(USER) - s_engine.getDebtReservedForAuction(USER);

        vm.prank(LIQUIDATOR);
        vm.expectRevert(
            abi.encodeWithSelector(
                StableCoinEngine.StableCoinEngine__DebtNotAvailableForLiquidation.selector, availableDebt, 600e18
            )
        );
        s_engine.liquidate(address(s_wbtc), USER, 600e18);
    }

    function testOnAuctionSettledRevertsOnlyLiquidationAuction() public {
        vm.expectRevert(StableCoinEngine.StableCoinEngine__OnlyLiquidationAuction.selector);
        s_engine.onAuctionSettled(0, 0, 0);
    }

    function testOnAuctionSettledRevertsAuctionNotActive() public {
        vm.prank(address(s_liquidationAuction));
        vm.expectRevert(abi.encodeWithSelector(StableCoinEngine.StableCoinEngine__AuctionNotActive.selector, 77));
        s_engine.onAuctionSettled(77, 0, 0);
    }

    function testOnAuctionSettledRevertsInvalidAuctionSettlement() public {
        _createActiveLiquidationAuction(1_000e18);

        vm.prank(address(s_liquidationAuction));
        vm.expectRevert(StableCoinEngine.StableCoinEngine__InvalidAuctionSettlement.selector);
        s_engine.onAuctionSettled(0, 1_000e18 + 1, 0);
    }

    function testOnAuctionSettledRevertsAuctionBurnExceedsDebt() public {
        _createActiveLiquidationAuction(1_000e18);

        stdstore.target(address(s_engine)).sig("getNormalizedDebt(address)").with_key(USER).checked_write(uint256(0));

        vm.prank(address(s_liquidationAuction));
        vm.expectRevert(
            abi.encodeWithSelector(StableCoinEngine.StableCoinEngine__AuctionBurnExceedsDebt.selector, 100e18, 0)
        );
        s_engine.onAuctionSettled(0, 100e18, 0);
    }

    function testGetUsdValueRevertsTokenNotAllowed() public {
        vm.expectRevert(abi.encodeWithSelector(StableCoinEngine.StableCoinEngine__TokenNotAllowed.selector, BAD_TOKEN));
        s_engine.getUsdValue(BAD_TOKEN, 1 ether);
    }

    function testGetUsdValueRevertsInvalidPrice() public {
        s_wethUsdFeed.updateAnswer(0);

        vm.expectRevert(OracleLib.OracleLib__InvalidPrice.selector);
        s_engine.getUsdValue(address(s_weth), 1 ether);
    }

    function testGetTokenAmountFromUsdRevertsTokenNotAllowed() public {
        vm.expectRevert(abi.encodeWithSelector(StableCoinEngine.StableCoinEngine__TokenNotAllowed.selector, BAD_TOKEN));
        s_engine.getTokenAmountFromUsd(BAD_TOKEN, 1e18);
    }

    function testGetTokenAmountFromUsdRevertsInvalidPrice() public {
        s_wethUsdFeed.updateAnswer(0);

        vm.expectRevert(OracleLib.OracleLib__InvalidPrice.selector);
        s_engine.getTokenAmountFromUsd(address(s_weth), 1e18);
    }

    function testTargetStabilityFeeBpsReturnsBaseWithinDeadbandBelowPeg() public {
        s_scUsdFeed.updateAnswer(99_950_000);
        assertEq(s_engine.getCurrentStabilityFeeBps(), 200);
    }

    function testTargetStabilityFeeBpsReturnsBaseWithinDeadbandAbovePeg() public {
        s_scUsdFeed.updateAnswer(100_050_000);
        assertEq(s_engine.getCurrentStabilityFeeBps(), 200);
    }

    function testTargetStabilityFeeBpsCapsAtMaxWhenFarBelowPeg() public {
        s_scUsdFeed.updateAnswer(20_000_000);
        assertEq(s_engine.getCurrentStabilityFeeBps(), 2_500);
    }

    function testTargetStabilityFeeBpsCapsAtMinWhenFarAbovePeg() public {
        s_scUsdFeed.updateAnswer(200_000_000);
        assertEq(s_engine.getCurrentStabilityFeeBps(), 0);
    }

    function testStableCoinPriceRevertsOnInvalidPrice() public {
        s_scUsdFeed.updateAnswer(0);

        vm.expectRevert(OracleLib.OracleLib__InvalidPrice.selector);
        s_engine.getCurrentStabilityFeeBps();
    }

    function testStableCoinPriceHandlesFeedDecimalsAbove18() public {
        (, StableCoinEngine highDecimalsEngine) = _deployEngineWithoutAuction(20, 1e20);
        assertEq(highDecimalsEngine.getCurrentStabilityFeeBps(), 200);
    }

    function testViewGettersReturnConfiguredState() public view {
        assertEq(s_engine.getPriceFeed(address(s_weth)), address(s_wethUsdFeed));
        assertEq(s_engine.getStableCoinAddress(), address(s_stableCoin));
        assertEq(s_engine.getStableCoinPriceFeed(), address(s_scUsdFeed));
        assertEq(s_engine.getLiquidationAuctionAddress(), address(s_liquidationAuction));
        assertEq(s_engine.getLiquidationBonus(), 10);
        assertEq(s_engine.getMinHealthFactor(), 1e18);
        assertEq(s_engine.getAppliedStabilityFeeBps(), 200);
        assertEq(s_engine.getLastStabilityFeeTimestamp(), block.timestamp);
        assertEq(s_engine.getMinStabilityFeeBps(), 0);
        assertEq(s_engine.getMaxStabilityFeeBps(), 2_500);
        assertEq(s_engine.getPegPrice(), 1e18);
    }

    function testGetPreviewRateUsesAccrualPathAfterTimeElapsed() public {
        uint256 rateBefore = s_engine.getRate();

        vm.warp(block.timestamp + 1 days);
        s_scUsdFeed.updateAnswer(SC_PRICE);

        uint256 previewRate = s_engine.getPreviewRate();
        assertGt(previewRate, rateBefore);
    }

    function testTargetStabilityFeeBpsReturnsReducedFeeAbovePegOutsideDeadband() public {
        s_scUsdFeed.updateAnswer(100_500_000);
        assertEq(s_engine.getCurrentStabilityFeeBps(), 120);
    }

    function testLiquidateSetsMinimumOpeningBidToOneForTinyDebt() public {
        _depositCollateral(USER, s_weth, 10 ether);

        vm.prank(USER);
        s_engine.mintStableCoin(9_500e18);

        vm.warp(block.timestamp + 31 minutes);
        s_wethUsdFeed.updateAnswer(1);

        vm.prank(LIQUIDATOR);
        s_engine.liquidate(address(s_weth), USER, 1);

        LiquidationAuction.Auction memory auction = s_liquidationAuction.getAuction(0);
        assertEq(auction.minimumBid, 1);
    }

    function _createActiveLiquidationAuction(uint256 debtToCover) internal {
        _depositCollateral(USER, s_weth, 10 ether);

        vm.prank(USER);
        s_engine.mintStableCoin(9_500e18);

        vm.warp(block.timestamp + 31 minutes);
        s_wethUsdFeed.updateAnswer(1_000e8);

        vm.prank(LIQUIDATOR);
        s_engine.liquidate(address(s_weth), USER, debtToCover);
    }

    function _depositCollateral(address user, ERC20Mock token, uint256 amount) internal {
        token.mint(user, amount);

        vm.startPrank(user);
        token.approve(address(s_engine), amount);
        s_engine.depositCollateral(address(token), amount);
        vm.stopPrank();
    }

    function _deployEngineWithoutAuction(uint8 stableCoinFeedDecimals, int256 stableCoinPrice)
        internal
        returns (StableCoin stableCoin, StableCoinEngine engine)
    {
        stableCoin = new StableCoin();

        ERC20Mock weth = new ERC20Mock();
        ERC20Mock wbtc = new ERC20Mock();

        MockV3Aggregator wethUsdFeed = new MockV3Aggregator(FEED_DECIMALS, WETH_PRICE);
        MockV3Aggregator wbtcUsdFeed = new MockV3Aggregator(FEED_DECIMALS, WBTC_PRICE);
        MockV3Aggregator scUsdFeed = new MockV3Aggregator(stableCoinFeedDecimals, stableCoinPrice);

        address[] memory collateralTokens = new address[](2);
        collateralTokens[0] = address(weth);
        collateralTokens[1] = address(wbtc);

        address[] memory priceFeeds = new address[](2);
        priceFeeds[0] = address(wethUsdFeed);
        priceFeeds[1] = address(wbtcUsdFeed);

        engine = new StableCoinEngine(collateralTokens, priceFeeds, address(stableCoin), address(scUsdFeed));
    }

}
