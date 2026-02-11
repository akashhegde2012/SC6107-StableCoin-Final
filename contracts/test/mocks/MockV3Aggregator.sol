// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title MockV3Aggregator
 * @notice Based on the FluxAggregator contract
 * @notice Use this contract when you need to test based on the V3 interface
 */
contract MockV3Aggregator {
    uint256 public constant version = 4;

    uint8 public decimals;
    int256 public latestAnswer;
    uint256 public latestTimestamp;
    uint256 public latestRound;

    mapping(uint256 => int256) public answers;
    mapping(uint256 => uint256) public timestamps;
    mapping(uint256 => uint256) public startedAt;

    constructor(uint8 _decimals, int256 _initialAnswer) {
        decimals = _decimals;
        updateAnswer(_initialAnswer);
    }

    function updateAnswer(int256 _answer) public {
        latestAnswer = _answer;
        latestTimestamp = block.timestamp;
        latestRound++;
        answers[latestRound] = _answer;
        timestamps[latestRound] = block.timestamp;
        startedAt[latestRound] = block.timestamp;
    }

    function updateRoundData(uint80 _roundId, int256 _answer, uint256 _timestamp, uint256 _startedAt) public {
        latestRound = _roundId;
        latestAnswer = _answer;
        latestTimestamp = _timestamp;
        answers[latestRound] = _answer;
        timestamps[latestRound] = _timestamp;
        startedAt[latestRound] = _startedAt;
    }

    function getRoundData(uint80 _roundId)
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt_, uint256 updatedAt, uint80 answeredInRound)
    {
        return (_roundId, answers[_roundId], startedAt[_roundId], timestamps[_roundId], _roundId);
    }

    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt_, uint256 updatedAt, uint80 answeredInRound)
    {
        return (uint80(latestRound), latestAnswer, startedAt[latestRound], latestTimestamp, uint80(latestRound));
    }

    function description() external pure returns (string memory) {
        return "v0.8/tests/MockV3Aggregator.sol";
    }
}
