// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AggregatorV3Interface} from "chainlink-brownie-contracts/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

/**
 * @title OracleLib
 * @author SCP Team
 * @notice Oracle guardrails for Chainlink-based pricing.
 * @dev Includes stale checks, optional multi-oracle validation, circuit breaker protection,
 * and TWAP smoothing to reduce single-read manipulation risk.
 */
library OracleLib {
    error OracleLib__StalePrice();
    error OracleLib__InvalidPrice();
    error OracleLib__InvalidOracleConfig();
    error OracleLib__CircuitBreakerTriggered(uint256 previousPrice, uint256 currentPrice, uint256 deviationBps);
    error OracleLib__OracleMismatch(uint256 primaryPrice, uint256 secondaryPrice, uint256 deviationBps);

    uint256 private constant TIMEOUT = 3 hours; // 3 * 60 * 60 = 10800 seconds
    uint256 private constant BPS_DENOMINATOR = 10_000;
    uint256 private constant DEFAULT_MAX_DEVIATION_BPS = 3_000; // 30%
    uint256 private constant DEFAULT_CIRCUIT_BREAKER_WINDOW = 30 minutes;
    uint256 private constant DEFAULT_CIRCUIT_BREAKER_RESET_WINDOW = 1 hours;
    uint256 private constant DEFAULT_TWAP_WINDOW = 30 minutes;

    struct OracleState {
        uint256 twapPrice;
        uint256 lastPrice;
        uint256 lastUpdateTimestamp;
        bool initialized;
    }

    struct OracleConfig {
        uint256 maxDeviationBps;
        uint256 shortCircuitBreakerWindow;
        uint256 circuitBreakerResetWindow;
        uint256 twapWindow;
    }

    function staleCheckLatestRoundData(AggregatorV3Interface priceFeed)
        public
        view
        returns (uint80, int256, uint256, uint256, uint80)
    {
        (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) =
            priceFeed.latestRoundData();

        uint256 secondsSinceLastUpdate = block.timestamp - updatedAt;
        if (secondsSinceLastUpdate > TIMEOUT) {
            revert OracleLib__StalePrice();
        }

        return (roundId, answer, startedAt, updatedAt, answeredInRound);
    }

    function readValidatedPrice(
        AggregatorV3Interface priceFeed,
        OracleState storage oracleState,
        OracleConfig memory oracleConfig
    ) internal returns (uint256) {
        return readValidatedPrice(priceFeed, AggregatorV3Interface(address(0)), oracleState, oracleConfig);
    }

    function readValidatedPrice(
        AggregatorV3Interface primaryFeed,
        AggregatorV3Interface secondaryFeed,
        OracleState storage oracleState,
        OracleConfig memory oracleConfig
    ) internal returns (uint256 validatedPrice) {
        OracleConfig memory resolvedConfig = _resolvedConfig(oracleConfig);
        uint256 primaryPrice = _normalizedPrice(primaryFeed);
        uint256 secondaryPrice = _secondaryPrice(secondaryFeed);

        if (!oracleState.initialized) {
            uint256 bootstrappedPrice = primaryPrice;
            if (secondaryPrice > 0) {
                _assertOracleAgreement(primaryPrice, secondaryPrice, resolvedConfig.maxDeviationBps);
                bootstrappedPrice = _averagePrice(primaryPrice, secondaryPrice);
            }

            oracleState.twapPrice = bootstrappedPrice;
            oracleState.lastPrice = primaryPrice;
            oracleState.lastUpdateTimestamp = block.timestamp;
            oracleState.initialized = true;
            return bootstrappedPrice;
        }

        uint256 elapsed = block.timestamp - oracleState.lastUpdateTimestamp;
        bool resetWindowPassed = elapsed > resolvedConfig.circuitBreakerResetWindow;

        if (!resetWindowPassed && elapsed > 0 && elapsed <= resolvedConfig.shortCircuitBreakerWindow) {
            uint256 circuitDeviationBps = _deviationBps(primaryPrice, oracleState.lastPrice);
            if (circuitDeviationBps > resolvedConfig.maxDeviationBps) {
                revert OracleLib__CircuitBreakerTriggered(oracleState.lastPrice, primaryPrice, circuitDeviationBps);
            }
        }

        uint256 previousTwap = oracleState.twapPrice == 0 ? oracleState.lastPrice : oracleState.twapPrice;
        uint256 nextTwap =
            resetWindowPassed ? primaryPrice : _calculateTwap(previousTwap, primaryPrice, elapsed, resolvedConfig.twapWindow);

        uint256 comparisonPrice = secondaryPrice == 0 ? nextTwap : secondaryPrice;
        _assertOracleAgreement(primaryPrice, comparisonPrice, resolvedConfig.maxDeviationBps);

        oracleState.twapPrice = nextTwap;
        oracleState.lastPrice = primaryPrice;
        oracleState.lastUpdateTimestamp = block.timestamp;

        return _averagePrice(primaryPrice, comparisonPrice);
    }

    function peekValidatedPrice(
        AggregatorV3Interface priceFeed,
        OracleState storage oracleState,
        OracleConfig memory oracleConfig
    ) internal view returns (uint256) {
        return peekValidatedPrice(priceFeed, AggregatorV3Interface(address(0)), oracleState, oracleConfig);
    }

    function peekValidatedPrice(
        AggregatorV3Interface primaryFeed,
        AggregatorV3Interface secondaryFeed,
        OracleState storage oracleState,
        OracleConfig memory oracleConfig
    ) internal view returns (uint256 validatedPrice) {
        OracleConfig memory resolvedConfig = _resolvedConfig(oracleConfig);
        uint256 primaryPrice = _normalizedPrice(primaryFeed);
        uint256 secondaryPrice = _secondaryPrice(secondaryFeed);

        if (!oracleState.initialized) {
            if (secondaryPrice > 0) {
                _assertOracleAgreement(primaryPrice, secondaryPrice, resolvedConfig.maxDeviationBps);
                return _averagePrice(primaryPrice, secondaryPrice);
            }
            return primaryPrice;
        }

        uint256 elapsed = block.timestamp - oracleState.lastUpdateTimestamp;
        bool resetWindowPassed = elapsed > resolvedConfig.circuitBreakerResetWindow;

        if (!resetWindowPassed && elapsed > 0 && elapsed <= resolvedConfig.shortCircuitBreakerWindow) {
            uint256 circuitDeviationBps = _deviationBps(primaryPrice, oracleState.lastPrice);
            if (circuitDeviationBps > resolvedConfig.maxDeviationBps) {
                revert OracleLib__CircuitBreakerTriggered(oracleState.lastPrice, primaryPrice, circuitDeviationBps);
            }
        }

        uint256 currentTwap = oracleState.twapPrice == 0 ? oracleState.lastPrice : oracleState.twapPrice;
        uint256 projectedTwap =
            resetWindowPassed ? primaryPrice : _calculateTwap(currentTwap, primaryPrice, elapsed, resolvedConfig.twapWindow);
        uint256 comparisonPrice = secondaryPrice == 0 ? projectedTwap : secondaryPrice;

        _assertOracleAgreement(primaryPrice, comparisonPrice, resolvedConfig.maxDeviationBps);

        return _averagePrice(primaryPrice, comparisonPrice);
    }

    function _resolvedConfig(OracleConfig memory oracleConfig) private pure returns (OracleConfig memory resolvedConfig) {
        resolvedConfig.maxDeviationBps =
            oracleConfig.maxDeviationBps == 0 ? DEFAULT_MAX_DEVIATION_BPS : oracleConfig.maxDeviationBps;
        resolvedConfig.shortCircuitBreakerWindow = oracleConfig.shortCircuitBreakerWindow == 0
            ? DEFAULT_CIRCUIT_BREAKER_WINDOW
            : oracleConfig.shortCircuitBreakerWindow;
        resolvedConfig.circuitBreakerResetWindow = oracleConfig.circuitBreakerResetWindow == 0
            ? DEFAULT_CIRCUIT_BREAKER_RESET_WINDOW
            : oracleConfig.circuitBreakerResetWindow;
        resolvedConfig.twapWindow = oracleConfig.twapWindow == 0 ? DEFAULT_TWAP_WINDOW : oracleConfig.twapWindow;

        if (resolvedConfig.maxDeviationBps >= BPS_DENOMINATOR) {
            revert OracleLib__InvalidOracleConfig();
        }

        if (resolvedConfig.circuitBreakerResetWindow < resolvedConfig.shortCircuitBreakerWindow) {
            resolvedConfig.circuitBreakerResetWindow = resolvedConfig.shortCircuitBreakerWindow;
        }
    }

    function _assertOracleAgreement(uint256 primaryPrice, uint256 referencePrice, uint256 maxDeviationBps) private pure {
        if (referencePrice == 0) {
            return;
        }

        uint256 deviationBps = _deviationBps(primaryPrice, referencePrice);
        if (deviationBps > maxDeviationBps) {
            revert OracleLib__OracleMismatch(primaryPrice, referencePrice, deviationBps);
        }
    }

    function _averagePrice(uint256 firstPrice, uint256 secondPrice) private pure returns (uint256) {
        if (firstPrice >= secondPrice) {
            return secondPrice + ((firstPrice - secondPrice) / 2);
        }
        return firstPrice + ((secondPrice - firstPrice) / 2);
    }

    function _secondaryPrice(AggregatorV3Interface secondaryFeed) private view returns (uint256) {
        if (address(secondaryFeed) == address(0)) {
            return 0;
        }

        return _normalizedPrice(secondaryFeed);
    }

    function _normalizedPrice(AggregatorV3Interface priceFeed) private view returns (uint256 normalizedPrice) {
        (, int256 answer,, uint256 updatedAt,) = priceFeed.latestRoundData();
        if (updatedAt == 0 || updatedAt > block.timestamp) {
            revert OracleLib__StalePrice();
        }

        uint256 secondsSinceLastUpdate = block.timestamp - updatedAt;
        if (secondsSinceLastUpdate > TIMEOUT) {
            revert OracleLib__StalePrice();
        }
        if (answer <= 0) {
            revert OracleLib__InvalidPrice();
        }

        uint8 feedDecimals = priceFeed.decimals();
        if (feedDecimals > 18) {
            normalizedPrice = uint256(answer) / (10 ** (feedDecimals - 18));
        } else {
            normalizedPrice = uint256(answer) * (10 ** (18 - feedDecimals));
        }
    }

    function _calculateTwap(uint256 previousTwap, uint256 currentPrice, uint256 elapsed, uint256 twapWindow)
        private
        pure
        returns (uint256)
    {
        if (twapWindow == 0 || elapsed >= twapWindow) {
            return currentPrice;
        }
        if (elapsed == 0) {
            return previousTwap;
        }

        uint256 previousWeight = twapWindow - elapsed;
        return ((previousTwap * previousWeight) + (currentPrice * elapsed)) / twapWindow;
    }

    function _deviationBps(uint256 currentPrice, uint256 referencePrice) private pure returns (uint256) {
        if (referencePrice == 0) {
            return type(uint256).max;
        }

        uint256 priceDelta = currentPrice >= referencePrice ? currentPrice - referencePrice : referencePrice - currentPrice;
        return (priceDelta * BPS_DENOMINATOR) / referencePrice;
    }
}
