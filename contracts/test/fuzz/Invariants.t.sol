// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {StdInvariant} from "forge-std/StdInvariant.sol";
import {Test} from "forge-std/Test.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

import {MockV3Aggregator} from "chainlink-brownie-contracts/contracts/src/v0.8/tests/MockV3Aggregator.sol";

import {StableCoin} from "../../src/StableCoin.sol";
import {StableCoinEngine} from "../../src/StableCoinEngine.sol";
import {Handler} from "./Handler.t.sol";

contract Invariants is StdInvariant, Test {
    uint8 private constant FEED_DECIMALS = 8;
    int256 private constant WETH_PRICE = 2_000e8;
    int256 private constant WBTC_PRICE = 30_000e8;
    int256 private constant SC_PRICE = 1e8;

    StableCoin private s_stableCoin;
    StableCoinEngine private s_engine;
    Handler private s_handler;

    ERC20Mock private s_weth;
    ERC20Mock private s_wbtc;

    function setUp() external {
        s_stableCoin = new StableCoin();
        s_weth = new ERC20Mock();
        s_wbtc = new ERC20Mock();

        MockV3Aggregator wethUsdFeed = new MockV3Aggregator(FEED_DECIMALS, WETH_PRICE);
        MockV3Aggregator wbtcUsdFeed = new MockV3Aggregator(FEED_DECIMALS, WBTC_PRICE);
        MockV3Aggregator stableCoinUsdFeed = new MockV3Aggregator(FEED_DECIMALS, SC_PRICE);

        address[] memory collateralTokens = new address[](2);
        collateralTokens[0] = address(s_weth);
        collateralTokens[1] = address(s_wbtc);

        address[] memory priceFeeds = new address[](2);
        priceFeeds[0] = address(wethUsdFeed);
        priceFeeds[1] = address(wbtcUsdFeed);

        s_engine = new StableCoinEngine(
            collateralTokens, priceFeeds, address(s_stableCoin), address(stableCoinUsdFeed)
        );
        s_stableCoin.grantRole(s_stableCoin.MINTER_ROLE(), address(s_engine));
        s_stableCoin.grantRole(s_stableCoin.BURNER_ROLE(), address(s_engine));

        s_handler = new Handler(s_engine, s_stableCoin);
        targetContract(address(s_handler));
    }

    function invariant_protocolIsAlwaysSolvent() external view {
        uint256 totalCollateralValueInUsd = s_engine.getUsdValue(address(s_weth), s_weth.balanceOf(address(s_engine)))
            + s_engine.getUsdValue(address(s_wbtc), s_wbtc.balanceOf(address(s_engine)));

        uint256 thresholdAdjustedCollateral = (totalCollateralValueInUsd * s_engine.getLiquidationThreshold()) / 100;
        assertGe(thresholdAdjustedCollateral, s_stableCoin.totalSupply());
    }
}
