// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {AggregatorV3Interface} from "chainlink-brownie-contracts/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

import {StableCoin} from "./StableCoin.sol";
import {OracleLib} from "./libraries/OracleLib.sol";

/**
 * @title PSM
 * @author SCP Team
 * @notice Price Stability Module for 1:1 swaps between supported stables and StableCoin.
 * @dev Requires MINTER_ROLE and BURNER_ROLE on StableCoin for this contract.
 */
contract PSM is ReentrancyGuard, Pausable {
    error PSM__ArrayLengthMismatch();
    error PSM__ZeroAddress();
    error PSM__AmountMustBeMoreThanZero();
    error PSM__UnsupportedCollateral(address token);
    error PSM__UnsupportedTokenDecimals(address token, uint8 decimals);
    error PSM__FeeTooHigh(uint16 feeBps);
    error PSM__AmountTooSmallAfterFee();
    error PSM__TransferFailed();
    error PSM__MintFailed();
    error PSM__InvalidPrice();
    error PSM__PegOutOfBounds(address token, uint256 normalizedPrice);
    error PSM__InsufficientLiquidity(address token, uint256 required, uint256 available);
    error PSM__NoFeesToCollect();

    event StableSwappedForStableCoin(
        address indexed user,
        address indexed collateralToken,
        uint256 collateralAmountIn,
        uint256 stableCoinAmountOut,
        uint256 feeAmount
    );
    event StableCoinSwappedForStable(
        address indexed user,
        address indexed collateralToken,
        uint256 stableCoinAmountIn,
        uint256 collateralAmountOut,
        uint256 feeAmount
    );
    event PegBoundsUpdated(uint256 lowerBound, uint256 upperBound);
    event TokenFeeBpsUpdated(address indexed token, uint16 feeBps);
    event TreasuryUpdated(address indexed oldTreasury, address indexed newTreasury);
    event FeesCollected(address indexed token, address indexed treasury, uint256 amount);
    event Unauthorized();

    struct TokenConfig {
        address priceFeed;
        uint8 decimals;
        uint16 feeBps;
        bool supported;
    }

    uint256 private constant BPS_DENOMINATOR = 10_000;
    uint256 private s_pegLowerBound = 99e16; // 0.99 USD
    uint256 private s_pegUpperBound = 101e16; // 1.01 USD
    uint256 private constant ORACLE_MAX_DEVIATION_BPS = 3_000; // 30%
    uint256 private constant ORACLE_CIRCUIT_BREAKER_WINDOW = 30 minutes;
    uint256 private constant ORACLE_CIRCUIT_BREAKER_RESET = 1 hours;
    uint256 private constant ORACLE_TWAP_WINDOW = 30 minutes;

    StableCoin private immutable i_stableCoin;
    address private s_treasury;
    mapping(address => TokenConfig) private s_tokenConfigs;
    mapping(address => OracleLib.OracleState) private s_oracleStates;
    mapping(address => uint256) private s_accumulatedFees;
    address[] private s_supportedCollateralTokens;

    modifier moreThanZero(uint256 amount) {
        if (amount == 0) {
            revert PSM__AmountMustBeMoreThanZero();
        }
        _;
    }

    modifier onlySupportedCollateral(address collateralToken) {
        if (!s_tokenConfigs[collateralToken].supported) {
            revert PSM__UnsupportedCollateral(collateralToken);
        }
        _;
    }

    constructor(
        address stableCoinAddress,
        address[] memory collateralTokens,
        address[] memory collateralPriceFeeds,
        uint16[] memory feeBpsByCollateral
    ) {
        if (stableCoinAddress == address(0)) {
            revert PSM__ZeroAddress();
        }

        uint256 length = collateralTokens.length;
        if (length == 0 || length != collateralPriceFeeds.length || length != feeBpsByCollateral.length) {
            revert PSM__ArrayLengthMismatch();
        }

        i_stableCoin = StableCoin(stableCoinAddress);

        for (uint256 i = 0; i < length; i++) {
            address token = collateralTokens[i];
            address feed = collateralPriceFeeds[i];
            uint16 feeBps = feeBpsByCollateral[i];

            if (token == address(0) || feed == address(0)) {
                revert PSM__ZeroAddress();
            }
            if (feeBps > BPS_DENOMINATOR) {
                revert PSM__FeeTooHigh(feeBps);
            }

            uint8 tokenDecimals = IERC20Metadata(token).decimals();
            if (tokenDecimals > 18) {
                revert PSM__UnsupportedTokenDecimals(token, tokenDecimals);
            }

            s_tokenConfigs[token] = TokenConfig({
                priceFeed: feed,
                decimals: tokenDecimals,
                feeBps: feeBps,
                supported: true
            });
            s_supportedCollateralTokens.push(token);
        }
    }

    modifier onlyAdmin() {
        if (!i_stableCoin.hasRole(i_stableCoin.DEFAULT_ADMIN_ROLE(), msg.sender)) {
            revert PSM__Unauthorized();
        }
        _;
    }

    error PSM__Unauthorized();

    function pause() external onlyAdmin {
        _pause();
    }

    function unpause() external onlyAdmin {
        _unpause();
    }

    function setPegBounds(uint256 lowerBound, uint256 upperBound) external onlyAdmin {
        emit PegBoundsUpdated(lowerBound, upperBound);
        s_pegLowerBound = lowerBound;
        s_pegUpperBound = upperBound;
    }

    function setTokenFeeBps(address token, uint16 feeBps) external onlyAdmin onlySupportedCollateral(token) {
        if (feeBps > BPS_DENOMINATOR) {
            revert PSM__FeeTooHigh(feeBps);
        }
        emit TokenFeeBpsUpdated(token, feeBps);
        s_tokenConfigs[token].feeBps = feeBps;
    }

    function setTreasury(address newTreasury) external onlyAdmin {
        if (newTreasury == address(0)) {
            revert PSM__ZeroAddress();
        }
        emit TreasuryUpdated(s_treasury, newTreasury);
        s_treasury = newTreasury;
    }

    function collectFees(address token) external onlyAdmin {
        uint256 amount = s_accumulatedFees[token];
        if (amount == 0) {
            revert PSM__NoFeesToCollect();
        }
        if (s_treasury == address(0)) {
            revert PSM__ZeroAddress();
        }

        s_accumulatedFees[token] = 0;
        bool success = IERC20(token).transfer(s_treasury, amount);
        if (!success) {
            revert PSM__TransferFailed();
        }

        emit FeesCollected(token, s_treasury, amount);
    }

    function swapStableForStableCoin(address collateralToken, uint256 collateralAmountIn)
        external
        moreThanZero(collateralAmountIn)
        onlySupportedCollateral(collateralToken)
        whenNotPaused
        nonReentrant
        returns (uint256 stableCoinAmountOut)
    {
        _checkPeg(collateralToken);

        TokenConfig memory config = s_tokenConfigs[collateralToken];
        uint256 feeAmount = _calculateFee(collateralAmountIn, config.feeBps);
        s_accumulatedFees[collateralToken] += feeAmount;
        uint256 amountAfterFee = collateralAmountIn - feeAmount;
        if (amountAfterFee == 0) {
            revert PSM__AmountTooSmallAfterFee();
        }

        bool success = IERC20(collateralToken).transferFrom(msg.sender, address(this), collateralAmountIn);
        if (!success) {
            revert PSM__TransferFailed();
        }

        stableCoinAmountOut = _to18Decimals(amountAfterFee, config.decimals);
        if (stableCoinAmountOut == 0) {
            revert PSM__AmountTooSmallAfterFee();
        }

        bool minted = i_stableCoin.mint(msg.sender, stableCoinAmountOut);
        if (!minted) {
            revert PSM__MintFailed();
        }

        emit StableSwappedForStableCoin(msg.sender, collateralToken, collateralAmountIn, stableCoinAmountOut, feeAmount);
    }

    function swapStableCoinForStable(address collateralToken, uint256 stableCoinAmountIn)
        external
        moreThanZero(stableCoinAmountIn)
        onlySupportedCollateral(collateralToken)
        whenNotPaused
        nonReentrant
        returns (uint256 collateralAmountOut)
    {
        _checkPeg(collateralToken);

        TokenConfig memory config = s_tokenConfigs[collateralToken];
        uint256 feeAmount = _calculateFee(stableCoinAmountIn, config.feeBps);
        uint256 amountAfterFee = stableCoinAmountIn - feeAmount;
        if (amountAfterFee == 0) {
            revert PSM__AmountTooSmallAfterFee();
        }

        collateralAmountOut = _from18Decimals(amountAfterFee, config.decimals);
        if (collateralAmountOut == 0) {
            revert PSM__AmountTooSmallAfterFee();
        }

        uint256 feeAmountInCollateral = _from18Decimals(stableCoinAmountIn, config.decimals) - collateralAmountOut;
        s_accumulatedFees[collateralToken] += feeAmountInCollateral;

        uint256 collateralBalance = IERC20(collateralToken).balanceOf(address(this));
        if (collateralBalance < collateralAmountOut) {
            revert PSM__InsufficientLiquidity(collateralToken, collateralAmountOut, collateralBalance);
        }

        i_stableCoin.burn(msg.sender, stableCoinAmountIn);

        bool success = IERC20(collateralToken).transfer(msg.sender, collateralAmountOut);
        if (!success) {
            revert PSM__TransferFailed();
        }

        emit StableCoinSwappedForStable(msg.sender, collateralToken, stableCoinAmountIn, collateralAmountOut, feeAmount);
    }

    function getStableCoinAddress() external view returns (address) {
        return address(i_stableCoin);
    }

    function getTokenConfig(address collateralToken) external view returns (TokenConfig memory) {
        return s_tokenConfigs[collateralToken];
    }

    function getSupportedCollateralTokens() external view returns (address[] memory) {
        return s_supportedCollateralTokens;
    }

    function getPegBounds() external view returns (uint256 lowerBound, uint256 upperBound) {
        return (s_pegLowerBound, s_pegUpperBound);
    }

    function getTreasury() external view returns (address) {
        return s_treasury;
    }

    function getAccumulatedFees(address token) external view returns (uint256) {
        return s_accumulatedFees[token];
    }

    function _checkPeg(address collateralToken) internal {
        uint256 normalizedPrice = _readNormalizedPrice(collateralToken);
        if (normalizedPrice < s_pegLowerBound || normalizedPrice > s_pegUpperBound) {
            revert PSM__PegOutOfBounds(collateralToken, normalizedPrice);
        }
    }

    function _getNormalizedPrice(address collateralToken) internal view returns (uint256 normalizedPrice) {
        return _peekNormalizedPrice(collateralToken);
    }

    function _readNormalizedPrice(address collateralToken) internal returns (uint256) {
        return OracleLib.readValidatedPrice(
            AggregatorV3Interface(s_tokenConfigs[collateralToken].priceFeed),
            s_oracleStates[collateralToken],
            _oracleConfig()
        );
    }

    function _peekNormalizedPrice(address collateralToken) internal view returns (uint256 normalizedPrice) {
        return OracleLib.peekValidatedPrice(
            AggregatorV3Interface(s_tokenConfigs[collateralToken].priceFeed),
            s_oracleStates[collateralToken],
            _oracleConfig()
        );
    }

    function _oracleConfig() internal pure returns (OracleLib.OracleConfig memory) {
        return OracleLib.OracleConfig({
            maxDeviationBps: ORACLE_MAX_DEVIATION_BPS,
            shortCircuitBreakerWindow: ORACLE_CIRCUIT_BREAKER_WINDOW,
            circuitBreakerResetWindow: ORACLE_CIRCUIT_BREAKER_RESET,
            twapWindow: ORACLE_TWAP_WINDOW
        });
    }

    function _calculateFee(uint256 amount, uint16 feeBps) internal pure returns (uint256) {
        return (amount * feeBps) / BPS_DENOMINATOR;
    }

    function _to18Decimals(uint256 amount, uint8 tokenDecimals) internal pure returns (uint256) {
        if (tokenDecimals == 18) {
            return amount;
        }
        return amount * (10 ** (18 - tokenDecimals));
    }

    function _from18Decimals(uint256 amount, uint8 tokenDecimals) internal pure returns (uint256) {
        if (tokenDecimals == 18) {
            return amount;
        }
        return amount / (10 ** (18 - tokenDecimals));
    }
}
