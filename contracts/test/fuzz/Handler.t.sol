// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

import {StableCoin} from "../../src/StableCoin.sol";
import {StableCoinEngine} from "../../src/StableCoinEngine.sol";

contract Handler is Test {
    StableCoinEngine private immutable i_engine;
    StableCoin private immutable i_stableCoin;
    address[] private s_collateralTokens;
    address[] private s_actors;
    mapping(address actor => bool exists) private s_isActor;

    uint256 private constant MAX_DEPOSIT_SIZE = 1_000_000 ether;

    constructor(StableCoinEngine engine, StableCoin stableCoin) {
        i_engine = engine;
        i_stableCoin = stableCoin;
        s_collateralTokens = engine.getCollateralTokens();
    }

    function depositCollateral(uint256 actorSeed, uint256 collateralSeed, uint256 amountCollateral) external {
        address actor = _actorFromSeed(actorSeed);
        address collateralToken = s_collateralTokens[collateralSeed % s_collateralTokens.length];
        uint256 amount = bound(amountCollateral, 1, MAX_DEPOSIT_SIZE);

        vm.startPrank(actor);
        ERC20Mock(collateralToken).mint(actor, amount);
        IERC20(collateralToken).approve(address(i_engine), amount);
        i_engine.depositCollateral(collateralToken, amount);
        vm.stopPrank();

        _addActor(actor);
    }

    function mintStableCoin(uint256 actorSeed, uint256 amountStableCoinToMint) external {
        if (s_actors.length == 0) {
            return;
        }

        address actor = s_actors[actorSeed % s_actors.length];
        (uint256 stableCoinMinted, uint256 collateralValueInUsd) = i_engine.getAccountInformation(actor);
        if (collateralValueInUsd == 0) {
            return;
        }

        uint256 maxMintable = (collateralValueInUsd * i_engine.getLiquidationThreshold()) / 100;
        if (maxMintable <= stableCoinMinted) {
            return;
        }

        uint256 amount = bound(amountStableCoinToMint, 1, maxMintable - stableCoinMinted);
        vm.prank(actor);
        i_engine.mintStableCoin(amount);
    }

    function burnStableCoin(uint256 actorSeed, uint256 amountStableCoinToBurn) external {
        if (s_actors.length == 0) {
            return;
        }

        address actor = s_actors[actorSeed % s_actors.length];
        uint256 minted = i_engine.getStableCoinMinted(actor);
        uint256 balance = i_stableCoin.balanceOf(actor);
        uint256 maxBurnable = minted < balance ? minted : balance;

        if (maxBurnable == 0) {
            return;
        }

        uint256 amount = bound(amountStableCoinToBurn, 1, maxBurnable);

        vm.startPrank(actor);
        i_stableCoin.approve(address(i_engine), amount);
        i_engine.burnStableCoin(amount);
        vm.stopPrank();
    }

    function redeemCollateral(uint256 actorSeed, uint256 collateralSeed, uint256 amountCollateralToRedeem) external {
        if (s_actors.length == 0) {
            return;
        }

        address actor = s_actors[actorSeed % s_actors.length];
        if (i_engine.getStableCoinMinted(actor) > 0) {
            return;
        }

        address collateralToken = s_collateralTokens[collateralSeed % s_collateralTokens.length];
        uint256 depositedCollateral = i_engine.getCollateralBalanceOfUser(actor, collateralToken);
        if (depositedCollateral == 0) {
            return;
        }

        uint256 amount = bound(amountCollateralToRedeem, 1, depositedCollateral);
        vm.prank(actor);
        i_engine.redeemCollateral(collateralToken, amount);
    }

    function getActors() external view returns (address[] memory) {
        return s_actors;
    }

    function _addActor(address actor) internal {
        if (!s_isActor[actor]) {
            s_isActor[actor] = true;
            s_actors.push(actor);
        }
    }

    function _actorFromSeed(uint256 seed) internal pure returns (address actor) {
        actor = address(uint160(uint256(keccak256(abi.encode(seed)))));
        if (actor == address(0)) {
            return address(1);
        }
    }
}
