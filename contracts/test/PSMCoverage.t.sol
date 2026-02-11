// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {MockV3Aggregator} from "chainlink-brownie-contracts/contracts/src/v0.8/tests/MockV3Aggregator.sol";

import {StableCoin} from "../src/StableCoin.sol";
import {PSM} from "../src/PSM.sol";

contract ERC20SixDecimalsCoverageMock is ERC20Mock {
    function decimals() public pure override returns (uint8) {
        return 6;
    }
}

contract ERC20NineteenDecimalsCoverageMock is ERC20Mock {
    function decimals() public pure override returns (uint8) {
        return 19;
    }
}

contract PSMCoverageTest is Test {
    uint16 private constant FULL_FEE_BPS = 10_000;
    uint16 private constant FEE_TOO_HIGH_BPS = 10_001;
    uint8 private constant STANDARD_FEED_DECIMALS = 8;
    int256 private constant STANDARD_PEG_PRICE = 1e8;

    address private constant USER = address(7);

    function testConstructorRevertsOnArrayLengthMismatch() public {
        StableCoin stableCoin = new StableCoin();
        ERC20Mock token = new ERC20Mock();
        MockV3Aggregator feed = new MockV3Aggregator(STANDARD_FEED_DECIMALS, STANDARD_PEG_PRICE);

        address[] memory collateralTokens = new address[](1);
        collateralTokens[0] = address(token);

        address[] memory collateralPriceFeeds = new address[](1);
        collateralPriceFeeds[0] = address(feed);

        uint16[] memory feeBpsByCollateral = new uint16[](0);

        vm.expectRevert(PSM.PSM__ArrayLengthMismatch.selector);
        new PSM(address(stableCoin), collateralTokens, collateralPriceFeeds, feeBpsByCollateral);
    }

    function testConstructorRevertsOnZeroStableCoinAddress() public {
        ERC20Mock token = new ERC20Mock();
        MockV3Aggregator feed = new MockV3Aggregator(STANDARD_FEED_DECIMALS, STANDARD_PEG_PRICE);

        address[] memory collateralTokens = new address[](1);
        collateralTokens[0] = address(token);

        address[] memory collateralPriceFeeds = new address[](1);
        collateralPriceFeeds[0] = address(feed);

        uint16[] memory feeBpsByCollateral = new uint16[](1);
        feeBpsByCollateral[0] = 0;

        vm.expectRevert(PSM.PSM__ZeroAddress.selector);
        new PSM(address(0), collateralTokens, collateralPriceFeeds, feeBpsByCollateral);
    }

    function testConstructorRevertsOnZeroCollateralTokenAddress() public {
        StableCoin stableCoin = new StableCoin();
        MockV3Aggregator feed = new MockV3Aggregator(STANDARD_FEED_DECIMALS, STANDARD_PEG_PRICE);

        address[] memory collateralTokens = new address[](1);
        collateralTokens[0] = address(0);

        address[] memory collateralPriceFeeds = new address[](1);
        collateralPriceFeeds[0] = address(feed);

        uint16[] memory feeBpsByCollateral = new uint16[](1);
        feeBpsByCollateral[0] = 0;

        vm.expectRevert(PSM.PSM__ZeroAddress.selector);
        new PSM(address(stableCoin), collateralTokens, collateralPriceFeeds, feeBpsByCollateral);
    }

    function testConstructorRevertsOnFeeTooHigh() public {
        StableCoin stableCoin = new StableCoin();
        ERC20Mock token = new ERC20Mock();
        MockV3Aggregator feed = new MockV3Aggregator(STANDARD_FEED_DECIMALS, STANDARD_PEG_PRICE);

        address[] memory collateralTokens = new address[](1);
        collateralTokens[0] = address(token);

        address[] memory collateralPriceFeeds = new address[](1);
        collateralPriceFeeds[0] = address(feed);

        uint16[] memory feeBpsByCollateral = new uint16[](1);
        feeBpsByCollateral[0] = FEE_TOO_HIGH_BPS;

        vm.expectRevert(abi.encodeWithSelector(PSM.PSM__FeeTooHigh.selector, FEE_TOO_HIGH_BPS));
        new PSM(address(stableCoin), collateralTokens, collateralPriceFeeds, feeBpsByCollateral);
    }

    function testConstructorRevertsOnUnsupportedTokenDecimals() public {
        StableCoin stableCoin = new StableCoin();
        ERC20NineteenDecimalsCoverageMock token = new ERC20NineteenDecimalsCoverageMock();
        MockV3Aggregator feed = new MockV3Aggregator(STANDARD_FEED_DECIMALS, STANDARD_PEG_PRICE);

        address[] memory collateralTokens = new address[](1);
        collateralTokens[0] = address(token);

        address[] memory collateralPriceFeeds = new address[](1);
        collateralPriceFeeds[0] = address(feed);

        uint16[] memory feeBpsByCollateral = new uint16[](1);
        feeBpsByCollateral[0] = 0;

        vm.expectRevert(abi.encodeWithSelector(PSM.PSM__UnsupportedTokenDecimals.selector, address(token), 19));
        new PSM(address(stableCoin), collateralTokens, collateralPriceFeeds, feeBpsByCollateral);
    }

    function testSwapStableForStableCoinRevertsWhenAmountAfterFeeIsZero() public {
        StableCoin stableCoin = new StableCoin();
        ERC20SixDecimalsCoverageMock token = new ERC20SixDecimalsCoverageMock();
        MockV3Aggregator feed = new MockV3Aggregator(STANDARD_FEED_DECIMALS, STANDARD_PEG_PRICE);
        PSM psm = _deploySingleTokenPsm(stableCoin, address(token), address(feed), FULL_FEE_BPS);

        uint256 amountIn = 1e6;
        _mintAndApprove(address(token), address(psm), USER, amountIn);

        vm.prank(USER);
        vm.expectRevert(PSM.PSM__AmountTooSmallAfterFee.selector);
        psm.swapStableForStableCoin(address(token), amountIn);
    }

    function testSwapStableCoinForStableRevertsWhenAmountAfterFeeIsZero() public {
        StableCoin stableCoin = new StableCoin();
        ERC20SixDecimalsCoverageMock token = new ERC20SixDecimalsCoverageMock();
        MockV3Aggregator feed = new MockV3Aggregator(STANDARD_FEED_DECIMALS, STANDARD_PEG_PRICE);
        PSM psm = _deploySingleTokenPsm(stableCoin, address(token), address(feed), FULL_FEE_BPS);

        vm.prank(USER);
        vm.expectRevert(PSM.PSM__AmountTooSmallAfterFee.selector);
        psm.swapStableCoinForStable(address(token), 1e18);
    }

    function testSwapStableCoinForStableRevertsWhenDownscaledAmountIsZero() public {
        StableCoin stableCoin = new StableCoin();
        ERC20SixDecimalsCoverageMock token = new ERC20SixDecimalsCoverageMock();
        MockV3Aggregator feed = new MockV3Aggregator(STANDARD_FEED_DECIMALS, STANDARD_PEG_PRICE);
        PSM psm = _deploySingleTokenPsm(stableCoin, address(token), address(feed), 0);

        vm.prank(USER);
        vm.expectRevert(PSM.PSM__AmountTooSmallAfterFee.selector);
        psm.swapStableCoinForStable(address(token), 1e11);
    }

    function testSwapStableForStableCoinUsesPriceFeedWithDecimalsGreaterThanEighteen() public {
        StableCoin stableCoin = new StableCoin();
        ERC20SixDecimalsCoverageMock token = new ERC20SixDecimalsCoverageMock();
        MockV3Aggregator feed = new MockV3Aggregator(20, 1e20);
        PSM psm = _deploySingleTokenPsm(stableCoin, address(token), address(feed), 0);

        uint256 amountIn = 1e6;
        _mintAndApprove(address(token), address(psm), USER, amountIn);

        vm.prank(USER);
        uint256 stableCoinOut = psm.swapStableForStableCoin(address(token), amountIn);

        assertEq(stableCoinOut, 1e18);
        assertEq(stableCoin.balanceOf(USER), 1e18);
    }

    function _deploySingleTokenPsm(StableCoin stableCoin, address collateralToken, address priceFeed, uint16 feeBps)
        internal
        returns (PSM)
    {
        address[] memory collateralTokens = new address[](1);
        collateralTokens[0] = collateralToken;

        address[] memory collateralPriceFeeds = new address[](1);
        collateralPriceFeeds[0] = priceFeed;

        uint16[] memory feeBpsByCollateral = new uint16[](1);
        feeBpsByCollateral[0] = feeBps;

        PSM psm = new PSM(address(stableCoin), collateralTokens, collateralPriceFeeds, feeBpsByCollateral);
        stableCoin.grantRole(stableCoin.MINTER_ROLE(), address(psm));
        stableCoin.grantRole(stableCoin.BURNER_ROLE(), address(psm));
        return psm;
    }

    function _mintAndApprove(address token, address spender, address user, uint256 amount) internal {
        ERC20Mock(token).mint(user, amount);

        vm.prank(user);
        ERC20Mock(token).approve(spender, amount);
    }
}
