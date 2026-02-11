// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {MockV3Aggregator} from "../test/mocks/MockV3Aggregator.sol";

contract DeploySCOracle is Script {
    function run() external returns (address scOracle) {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerKey);

        // SC price feed: $1.00 with 8 decimals
        MockV3Aggregator oracle = new MockV3Aggregator(8, 1e8);

        vm.stopBroadcast();
        return address(oracle);
    }
}
