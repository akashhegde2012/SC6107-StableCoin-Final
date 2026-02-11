// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";

import {StableCoin} from "../src/StableCoin.sol";
import {StableCoinEngine} from "../src/StableCoinEngine.sol";
import {PSM} from "../src/PSM.sol";
import {LiquidationAuction} from "../src/LiquidationAuction.sol";
import {OracleLib} from "../src/libraries/OracleLib.sol";

import {DeployStableCoin} from "../script/Deploy.s.sol";
import {HelperConfig} from "../script/HelperConfig.s.sol";

import {ERC20Mock} from "./mocks/ERC20Mock.sol";
import {MockV3Aggregator} from "./mocks/MockV3Aggregator.sol";

contract IntegrationTest is Test {
    uint256 private constant USER_COLLATERAL = 10 ether;
    uint256 private constant DEBT_TO_MINT = 9_000e18;
    uint256 private constant LIQUIDATION_DEBT = 1_000e18;
    uint256 private constant BIDDER_COLLATERAL = 1 ether;

    uint256 private constant PSM_SWAP_IN = 1_000e18;
    uint256 private constant ENGINE_MINT_AFTER_PSM = 500e18;

    uint256 private constant HEALTH_CHECK_MINT = 5_000e18;

    int256 private constant ETH_PRICE = 2_000e8;
    int256 private constant ETH_PRICE_AFTER_DROP = 1_000e8;
    int256 private constant PEG_PRICE = 1e8;
    int256 private constant BELOW_PEG_PRICE = 98e6;

    StableCoin private s_stableCoin;
    StableCoinEngine private s_engine;
    PSM private s_psm;
    LiquidationAuction private s_auction;

    ERC20Mock private s_weth;
    ERC20Mock private s_wbtc;

    MockV3Aggregator private s_wethUsdFeed;
    MockV3Aggregator private s_stableCoinUsdFeed;

    function setUp() public {
        DeployStableCoin deployer = new DeployStableCoin();
        HelperConfig helperConfig;
        (s_stableCoin, s_engine, s_psm, s_auction, helperConfig) = deployer.run();

        HelperConfig.NetworkConfig memory config = helperConfig.getActiveNetworkConfig();

        s_weth = ERC20Mock(config.collateralTokens[0]);
        s_wbtc = ERC20Mock(config.collateralTokens[1]);
        s_wethUsdFeed = MockV3Aggregator(config.priceFeeds[0]);
        s_stableCoinUsdFeed = MockV3Aggregator(config.stableCoinPriceFeed);
    }

    function testUserLifecycleLiquidationAuctionFlowClearsReservedDebt() public {
        address user = makeAddr("user");
        address bidder = makeAddr("bidder");

        _mintAndDepositCollateral(user, s_weth, USER_COLLATERAL);

        vm.prank(user);
        s_engine.mintStableCoin(DEBT_TO_MINT);

        vm.warp(block.timestamp + 31 minutes);
        s_wethUsdFeed.updateAnswer(ETH_PRICE_AFTER_DROP);

        _mintAndDepositCollateral(bidder, s_wbtc, BIDDER_COLLATERAL);

        vm.prank(bidder);
        s_engine.mintStableCoin(2_000e18);

        uint256 debtBeforeLiquidation = s_engine.getStableCoinMinted(user);

        vm.prank(bidder);
        s_engine.liquidate(address(s_weth), user, LIQUIDATION_DEBT);

        (address auctionUser, address auctionToken, uint256 debtToCover, uint256 collateralAmount, bool active) =
            s_engine.getPendingLiquidationAuction(0);

        assertEq(auctionUser, user);
        assertEq(auctionToken, address(s_weth));
        assertEq(debtToCover, LIQUIDATION_DEBT);
        assertEq(collateralAmount, 1.1 ether);
        assertTrue(active);

        vm.startPrank(bidder);
        s_stableCoin.approve(address(s_auction), LIQUIDATION_DEBT);
        s_auction.placeBid(0, LIQUIDATION_DEBT);
        vm.stopPrank();

        s_engine.finalizeLiquidationAuction(0);

        LiquidationAuction.Auction memory auction = s_auction.getAuction(0);
        assertTrue(auction.settled);
        assertEq(auction.highestBidder, bidder);
        assertApproxEqAbs(s_engine.getStableCoinMinted(user), debtBeforeLiquidation - LIQUIDATION_DEBT, 1);
        assertEq(s_engine.getDebtReservedForAuction(user), 0);
        assertFalse(s_engine.hasActiveLiquidationAuction(user, address(s_weth)));
        assertEq(s_stableCoin.balanceOf(address(s_engine)), 0);
        assertEq(s_weth.balanceOf(bidder), 1.1 ether);
    }

    function testPsmSwapThenOpenCdpWithSameStableCoinAsset() public {
        address user = makeAddr("psmUser");

        s_wethUsdFeed.updateAnswer(PEG_PRICE);

        s_weth.mint(user, PSM_SWAP_IN);
        vm.startPrank(user);
        s_weth.approve(address(s_psm), PSM_SWAP_IN);
        uint256 stableCoinFromPsm = s_psm.swapStableForStableCoin(address(s_weth), PSM_SWAP_IN);
        vm.stopPrank();

        uint256 expectedPsmOutput = PSM_SWAP_IN - ((PSM_SWAP_IN * 10) / 10_000);
        assertEq(stableCoinFromPsm, expectedPsmOutput);

        _mintAndDepositCollateral(user, s_wbtc, BIDDER_COLLATERAL);

        vm.prank(user);
        s_engine.mintStableCoin(ENGINE_MINT_AFTER_PSM);

        assertEq(s_engine.getStableCoinMinted(user), ENGINE_MINT_AFTER_PSM);
        assertEq(s_stableCoin.balanceOf(user), stableCoinFromPsm + ENGINE_MINT_AFTER_PSM);
    }

    function testStabilityFeeAccrualIncreasesDebtAndReducesHealthFactor() public {
        address user = makeAddr("feeUser");

        _mintAndDepositCollateral(user, s_weth, USER_COLLATERAL);

        vm.prank(user);
        s_engine.mintStableCoin(HEALTH_CHECK_MINT);

        uint256 initialDebt = s_engine.getStableCoinMinted(user);
        uint256 initialHealthFactor = s_engine.getHealthFactor(user);

        vm.warp(block.timestamp + 4 hours);
        vm.expectRevert(OracleLib.OracleLib__StalePrice.selector);
        s_engine.dripStabilityFee();

        s_stableCoinUsdFeed.updateAnswer(BELOW_PEG_PRICE);
        s_wethUsdFeed.updateAnswer(ETH_PRICE);

        vm.warp(block.timestamp + 30 days);
        s_stableCoinUsdFeed.updateAnswer(BELOW_PEG_PRICE);
        s_wethUsdFeed.updateAnswer(ETH_PRICE);

        s_engine.dripStabilityFee();

        uint256 debtAfterAccrual = s_engine.getStableCoinMinted(user);
        uint256 healthFactorAfterAccrual = s_engine.getHealthFactor(user);

        assertGt(debtAfterAccrual, initialDebt);
        assertLt(healthFactorAfterAccrual, initialHealthFactor);
    }

    function _mintAndDepositCollateral(address user, ERC20Mock token, uint256 amount) internal {
        token.mint(user, amount);

        vm.startPrank(user);
        token.approve(address(s_engine), amount);
        s_engine.depositCollateral(address(token), amount);
        vm.stopPrank();
    }
}
