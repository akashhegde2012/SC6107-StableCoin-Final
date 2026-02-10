// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {MockV3Aggregator} from "chainlink-brownie-contracts/contracts/src/v0.8/tests/MockV3Aggregator.sol";

import {StableCoin} from "../src/StableCoin.sol";
import {PSM} from "../src/PSM.sol";
import {OracleLib} from "../src/libraries/OracleLib.sol";

contract ERC20SixDecimalsMock is ERC20Mock {
    function decimals() public pure override returns (uint8) {
        return 6;
    }
}

contract PSMTest is Test {
    uint8 private constant FEED_DECIMALS = 8;
    int256 private constant PEG_PRICE = 1e8;

    uint16 private constant USDC_FEE_BPS = 30;
    uint16 private constant DAI_FEE_BPS = 50;
    uint256 private constant BPS_DENOMINATOR = 10_000;

    address private constant USER = address(1);

    StableCoin private s_stableCoin;
    PSM private s_psm;

    ERC20SixDecimalsMock private s_usdc;
    ERC20Mock private s_dai;

    MockV3Aggregator private s_usdcUsdFeed;
    MockV3Aggregator private s_daiUsdFeed;

    function setUp() public {
        s_stableCoin = new StableCoin();
        s_usdc = new ERC20SixDecimalsMock();
        s_dai = new ERC20Mock();

        s_usdcUsdFeed = new MockV3Aggregator(FEED_DECIMALS, PEG_PRICE);
        s_daiUsdFeed = new MockV3Aggregator(FEED_DECIMALS, PEG_PRICE);

        s_psm = _deployPsm(USDC_FEE_BPS, DAI_FEE_BPS);
    }

    function testSwapStableForStableCoinChargesFeeAndNormalizesSixDecimals() public {
        uint256 collateralAmountIn = 100e6;
        _mintAndApprove(address(s_usdc), address(s_psm), USER, collateralAmountIn);

        uint256 expectedFee = (collateralAmountIn * USDC_FEE_BPS) / BPS_DENOMINATOR;
        uint256 expectedStableCoinOut = (collateralAmountIn - expectedFee) * 1e12;

        vm.prank(USER);
        uint256 stableCoinAmountOut = s_psm.swapStableForStableCoin(address(s_usdc), collateralAmountIn);

        assertEq(stableCoinAmountOut, expectedStableCoinOut);
        assertEq(s_stableCoin.balanceOf(USER), expectedStableCoinOut);
        assertEq(s_usdc.balanceOf(address(s_psm)), collateralAmountIn);
    }

    function testSwapStableCoinForStableChargesFeeAndNormalizesToSixDecimals() public {
        uint256 collateralAmountIn = 100e6;
        _mintAndApprove(address(s_usdc), address(s_psm), USER, collateralAmountIn);

        vm.startPrank(USER);
        uint256 mintedStableCoin = s_psm.swapStableForStableCoin(address(s_usdc), collateralAmountIn);

        uint256 stableCoinAmountIn = 50e18;
        uint256 collateralAmountOut = s_psm.swapStableCoinForStable(address(s_usdc), stableCoinAmountIn);
        vm.stopPrank();

        uint256 expectedFee = (stableCoinAmountIn * USDC_FEE_BPS) / BPS_DENOMINATOR;
        uint256 expectedCollateralOut = (stableCoinAmountIn - expectedFee) / 1e12;

        assertEq(collateralAmountOut, expectedCollateralOut);
        assertEq(s_usdc.balanceOf(USER), expectedCollateralOut);
        assertEq(s_stableCoin.balanceOf(USER), mintedStableCoin - stableCoinAmountIn);
        assertEq(s_usdc.balanceOf(address(s_psm)), collateralAmountIn - expectedCollateralOut);
    }

    function testSwapStableForStableCoinKeepsEighteenDecimalsForEighteenDecimalToken() public {
        uint256 collateralAmountIn = 10e18;
        _mintAndApprove(address(s_dai), address(s_psm), USER, collateralAmountIn);

        uint256 expectedFee = (collateralAmountIn * DAI_FEE_BPS) / BPS_DENOMINATOR;
        uint256 expectedStableCoinOut = collateralAmountIn - expectedFee;

        vm.prank(USER);
        uint256 stableCoinAmountOut = s_psm.swapStableForStableCoin(address(s_dai), collateralAmountIn);

        assertEq(stableCoinAmountOut, expectedStableCoinOut);
        assertEq(s_stableCoin.balanceOf(USER), expectedStableCoinOut);
    }

    function testRoundTripSixDecimalsWithZeroFeeHasNoDecimalLoss() public {
        PSM zeroFeePsm = _deployPsm(0, 0);

        uint256 collateralAmountIn = 1_234_567;
        _mintAndApprove(address(s_usdc), address(zeroFeePsm), USER, collateralAmountIn);

        vm.startPrank(USER);
        uint256 stableCoinAmountOut = zeroFeePsm.swapStableForStableCoin(address(s_usdc), collateralAmountIn);
        uint256 collateralAmountOut = zeroFeePsm.swapStableCoinForStable(address(s_usdc), stableCoinAmountOut);
        vm.stopPrank();

        assertEq(stableCoinAmountOut, collateralAmountIn * 1e12);
        assertEq(collateralAmountOut, collateralAmountIn);
        assertEq(s_stableCoin.balanceOf(USER), 0);
    }

    function testSwapStableForStableCoinRevertsWhenPegBelowLowerBound() public {
        uint256 collateralAmountIn = 1e6;
        _mintAndApprove(address(s_usdc), address(s_psm), USER, collateralAmountIn);

        s_usdcUsdFeed.updateAnswer(98_000_000);

        vm.prank(USER);
        vm.expectRevert(abi.encodeWithSelector(PSM.PSM__PegOutOfBounds.selector, address(s_usdc), 98e16));
        s_psm.swapStableForStableCoin(address(s_usdc), collateralAmountIn);
    }

    function testSwapStableCoinForStableRevertsWhenPegAboveUpperBound() public {
        uint256 collateralAmountIn = 10e6;
        _mintAndApprove(address(s_usdc), address(s_psm), USER, collateralAmountIn);

        vm.prank(USER);
        s_psm.swapStableForStableCoin(address(s_usdc), collateralAmountIn);

        vm.warp(block.timestamp + 31 minutes);
        s_usdcUsdFeed.updateAnswer(102_000_000);

        vm.prank(USER);
        vm.expectRevert(abi.encodeWithSelector(PSM.PSM__PegOutOfBounds.selector, address(s_usdc), 102e16));
        s_psm.swapStableCoinForStable(address(s_usdc), 1e18);
    }

    function testSwapStableForStableCoinRevertsWhenOraclePriceIsNonPositive() public {
        uint256 collateralAmountIn = 1e6;
        _mintAndApprove(address(s_usdc), address(s_psm), USER, collateralAmountIn);

        s_usdcUsdFeed.updateAnswer(0);

        vm.prank(USER);
        vm.expectRevert(OracleLib.OracleLib__InvalidPrice.selector);
        s_psm.swapStableForStableCoin(address(s_usdc), collateralAmountIn);
    }

    function testSwapStableCoinForStableRevertsWhenPsmLiquidityIsInsufficient() public {
        uint256 collateralAmountIn = 10e6;
        _mintAndApprove(address(s_usdc), address(s_psm), USER, collateralAmountIn);

        vm.prank(USER);
        s_psm.swapStableForStableCoin(address(s_usdc), collateralAmountIn);

        uint256 stableCoinAmountIn = 20e18;
        uint256 expectedFee = (stableCoinAmountIn * USDC_FEE_BPS) / BPS_DENOMINATOR;
        uint256 requiredCollateral = (stableCoinAmountIn - expectedFee) / 1e12;

        vm.prank(USER);
        vm.expectRevert(
            abi.encodeWithSelector(
                PSM.PSM__InsufficientLiquidity.selector, address(s_usdc), requiredCollateral, collateralAmountIn
            )
        );
        s_psm.swapStableCoinForStable(address(s_usdc), stableCoinAmountIn);
    }

    function testSwapStableForStableCoinRevertsOnZeroAmount() public {
        vm.prank(USER);
        vm.expectRevert(PSM.PSM__AmountMustBeMoreThanZero.selector);
        s_psm.swapStableForStableCoin(address(s_usdc), 0);
    }

    function testSwapStableCoinForStableRevertsOnZeroAmount() public {
        vm.prank(USER);
        vm.expectRevert(PSM.PSM__AmountMustBeMoreThanZero.selector);
        s_psm.swapStableCoinForStable(address(s_usdc), 0);
    }

    function _deployPsm(uint16 usdcFeeBps, uint16 daiFeeBps) internal returns (PSM psm) {
        address[] memory collateralTokens = new address[](2);
        collateralTokens[0] = address(s_usdc);
        collateralTokens[1] = address(s_dai);

        address[] memory priceFeeds = new address[](2);
        priceFeeds[0] = address(s_usdcUsdFeed);
        priceFeeds[1] = address(s_daiUsdFeed);

        uint16[] memory feeBpsByCollateral = new uint16[](2);
        feeBpsByCollateral[0] = usdcFeeBps;
        feeBpsByCollateral[1] = daiFeeBps;

        psm = new PSM(address(s_stableCoin), collateralTokens, priceFeeds, feeBpsByCollateral);
        s_stableCoin.grantRole(s_stableCoin.MINTER_ROLE(), address(psm));
        s_stableCoin.grantRole(s_stableCoin.BURNER_ROLE(), address(psm));
    }

    function _mintAndApprove(address token, address spender, address user, uint256 amount) internal {
        ERC20Mock(token).mint(user, amount);

        vm.prank(user);
        ERC20Mock(token).approve(spender, amount);
    }
}
