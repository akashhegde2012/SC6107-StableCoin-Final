// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {MockV3Aggregator} from "../test/mocks/MockV3Aggregator.sol";
import {ERC20Mock} from "../test/mocks/ERC20Mock.sol";

contract HelperConfig is Script {
    struct NetworkConfig {
        address[] collateralTokens;
        address[] priceFeeds;
        address stableCoinPriceFeed;
        uint16[] psmFeeBps;
        uint256 deployerKey;
    }

    NetworkConfig public activeNetworkConfig;

    uint8 public constant DECIMALS = 8;
    int256 public constant ETH_USD_PRICE = 2000e8;
    int256 public constant BTC_USD_PRICE = 30000e8;
    int256 public constant SC_USD_PRICE = 1e8;

    constructor() {
        if (block.chainid == 11155111) {
            activeNetworkConfig = getSepoliaEthConfig();
        } else if (block.chainid == 1) {
            activeNetworkConfig = getMainnetEthConfig();
        } else {
            activeNetworkConfig = getOrCreateAnvilEthConfig();
        }
    }

    function getSepoliaEthConfig() public returns (NetworkConfig memory) {
        address[] memory collateralTokens = new address[](2);
        collateralTokens[0] = 0x4665313Bcf83ef598378A92e066c58A136334479; // Mock WETH
        collateralTokens[1] = 0x45e4F73c826a27A984C76E385Ae34DDa904d9fcB; // Mock WBTC

        address[] memory priceFeeds = new address[](2);
        priceFeeds[0] = 0x694AA1769357215DE4FAC081bf1f309aDC325306; // ETH/USD
        priceFeeds[1] = 0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43; // BTC/USD

        uint16[] memory psmFeeBps = new uint16[](2);
        psmFeeBps[0] = 10;
        psmFeeBps[1] = 10;

        return NetworkConfig({
            collateralTokens: collateralTokens,
            priceFeeds: priceFeeds,
            stableCoinPriceFeed: 0x26818a983a4c93D211515d142B77c6566EdfE2E7, // Mock SC Oracle ($1.00)
            psmFeeBps: psmFeeBps,
            deployerKey: vm.envUint("PRIVATE_KEY")
        });
    }

    function getMainnetEthConfig() public pure returns (NetworkConfig memory) {
        address[] memory collateralTokens = new address[](2);
        collateralTokens[0] = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2; // WETH
        collateralTokens[1] = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599; // WBTC

        address[] memory priceFeeds = new address[](2);
        priceFeeds[0] = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419; // ETH/USD
        priceFeeds[1] = 0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c; // BTC/USD

        uint16[] memory psmFeeBps = new uint16[](2);
        psmFeeBps[0] = 10;
        psmFeeBps[1] = 10;

        return NetworkConfig({
            collateralTokens: collateralTokens,
            priceFeeds: priceFeeds,
            stableCoinPriceFeed: 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419, // Placeholder
            psmFeeBps: psmFeeBps,
            deployerKey: 0 // Should be set via env
        });
    }

    function getOrCreateAnvilEthConfig() public returns (NetworkConfig memory) {
        if (activeNetworkConfig.collateralTokens.length > 0) {
            return activeNetworkConfig;
        }

        vm.startBroadcast();
        MockV3Aggregator ethUsdPriceFeed = new MockV3Aggregator(DECIMALS, ETH_USD_PRICE);
        ERC20Mock wethMock = new ERC20Mock("WETH", "WETH", msg.sender, 1000e18);

        MockV3Aggregator btcUsdPriceFeed = new MockV3Aggregator(DECIMALS, BTC_USD_PRICE);
        ERC20Mock wbtcMock = new ERC20Mock("WBTC", "WBTC", msg.sender, 1000e18);

        MockV3Aggregator scUsdPriceFeed = new MockV3Aggregator(DECIMALS, SC_USD_PRICE);
        vm.stopBroadcast();

        address[] memory collateralTokens = new address[](2);
        collateralTokens[0] = address(wethMock);
        collateralTokens[1] = address(wbtcMock);

        address[] memory priceFeeds = new address[](2);
        priceFeeds[0] = address(ethUsdPriceFeed);
        priceFeeds[1] = address(btcUsdPriceFeed);

        uint16[] memory psmFeeBps = new uint16[](2);
        psmFeeBps[0] = 10;
        psmFeeBps[1] = 10;

        return NetworkConfig({
            collateralTokens: collateralTokens,
            priceFeeds: priceFeeds,
            stableCoinPriceFeed: address(scUsdPriceFeed),
            psmFeeBps: psmFeeBps,
            deployerKey: 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
        });
    }

    function getActiveNetworkConfig() public view returns (NetworkConfig memory) {
        return activeNetworkConfig;
    }
}
