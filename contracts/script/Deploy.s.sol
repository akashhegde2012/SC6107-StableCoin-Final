// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {StableCoin} from "../src/StableCoin.sol";
import {StableCoinEngine} from "../src/StableCoinEngine.sol";
import {PSM} from "../src/PSM.sol";
import {LiquidationAuction} from "../src/LiquidationAuction.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

contract DeployStableCoin is Script {
    function run() external returns (StableCoin, StableCoinEngine, PSM, LiquidationAuction, HelperConfig) {
        HelperConfig helperConfig = new HelperConfig();
        HelperConfig.NetworkConfig memory config = helperConfig.getActiveNetworkConfig();
        address[] memory collateralTokens = config.collateralTokens;
        address[] memory priceFeeds = config.priceFeeds;
        address stableCoinPriceFeed = config.stableCoinPriceFeed;
        uint16[] memory psmFeeBps = config.psmFeeBps;
        uint256 deployerKey = config.deployerKey;

        vm.startBroadcast(deployerKey);
        StableCoin stableCoin = new StableCoin();

        StableCoinEngine engine = new StableCoinEngine(
            collateralTokens,
            priceFeeds,
            address(stableCoin),
            stableCoinPriceFeed
        );

        LiquidationAuction auction = new LiquidationAuction(
            address(stableCoin),
            address(engine)
        );

        PSM psm = new PSM(
            address(stableCoin),
            collateralTokens,
            priceFeeds,
            psmFeeBps
        );

        // Grant roles
        stableCoin.grantRole(stableCoin.MINTER_ROLE(), address(engine));
        stableCoin.grantRole(stableCoin.BURNER_ROLE(), address(engine));
        stableCoin.grantRole(stableCoin.MINTER_ROLE(), address(psm));
        stableCoin.grantRole(stableCoin.BURNER_ROLE(), address(psm));

        // Configure engine
        engine.setLiquidationAuction(address(auction));

        vm.stopBroadcast();

        return (stableCoin, engine, psm, auction, helperConfig);
    }
}
