// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

import {StableCoin} from "../src/StableCoin.sol";
import {LiquidationAuction} from "../src/LiquidationAuction.sol";

contract MockLiquidationEngine {
    error MockLiquidationEngine__AuctionAlreadySet();
    error MockLiquidationEngine__AuctionNotSet();
    error MockLiquidationEngine__OnlyAuction();
    error MockLiquidationEngine__TransferFailed();

    StableCoin private immutable i_stableCoin;
    LiquidationAuction private s_auction;

    uint256 private s_totalBurned;
    uint256 private s_lastAuctionId;
    uint256 private s_lastStableCoinToBurn;
    uint256 private s_lastCollateralToReturn;

    constructor(address stableCoin) {
        i_stableCoin = StableCoin(stableCoin);
    }

    function setAuction(address auction) external {
        if (address(s_auction) != address(0)) {
            revert MockLiquidationEngine__AuctionAlreadySet();
        }
        s_auction = LiquidationAuction(auction);
    }

    function startAuction(
        address user,
        address collateralToken,
        uint256 collateralAmount,
        uint256 targetDebt,
        uint256 minimumBid,
        uint256 duration
    ) external returns (uint256 auctionId) {
        if (address(s_auction) == address(0)) {
            revert MockLiquidationEngine__AuctionNotSet();
        }

        if (collateralToken != address(0)) {
            bool success = IERC20(collateralToken).transfer(address(s_auction), collateralAmount);
            if (!success) {
                revert MockLiquidationEngine__TransferFailed();
            }
        }

        auctionId = s_auction.createAuction(user, collateralToken, collateralAmount, targetDebt, minimumBid, duration);
    }

    function onAuctionSettled(uint256 auctionId, uint256 stableCoinToBurn, uint256 collateralToReturn) external {
        if (msg.sender != address(s_auction)) {
            revert MockLiquidationEngine__OnlyAuction();
        }

        s_lastAuctionId = auctionId;
        s_lastStableCoinToBurn = stableCoinToBurn;
        s_lastCollateralToReturn = collateralToReturn;

        if (stableCoinToBurn > 0) {
            s_totalBurned += stableCoinToBurn;
            i_stableCoin.burn(address(this), stableCoinToBurn);
        }
    }

    function getTotalBurned() external view returns (uint256) {
        return s_totalBurned;
    }

    function getLastSettlement() external view returns (uint256 auctionId, uint256 stableCoinToBurn, uint256 collateralToReturn) {
        return (s_lastAuctionId, s_lastStableCoinToBurn, s_lastCollateralToReturn);
    }
}

contract LiquidationAuctionCoverageTest is Test {
    uint256 private constant AUCTION_DURATION = 2 hours;
    uint256 private constant TARGET_DEBT = 1_000e18;
    uint256 private constant MIN_OPENING_BID = 800e18;
    uint256 private constant COLLATERAL_AMOUNT = 1.1 ether;

    address private constant USER = address(1);
    address private constant BIDDER_ONE = address(2);

    StableCoin private s_stableCoin;
    ERC20Mock private s_collateral;
    MockLiquidationEngine private s_engine;
    LiquidationAuction private s_auction;

    function setUp() public {
        s_stableCoin = new StableCoin();
        s_collateral = new ERC20Mock();
        s_engine = new MockLiquidationEngine(address(s_stableCoin));
        s_auction = new LiquidationAuction(address(s_stableCoin), address(s_engine));
        s_engine.setAuction(address(s_auction));

        s_stableCoin.grantRole(s_stableCoin.MINTER_ROLE(), address(this));
        s_stableCoin.grantRole(s_stableCoin.BURNER_ROLE(), address(s_engine));
    }

    function testGetters() public {
        assertEq(s_auction.getStableCoinAddress(), address(s_stableCoin));
        assertEq(s_auction.getEngineAddress(), address(s_engine));
        assertEq(s_auction.getNextAuctionId(), 0);
        assertEq(s_auction.getMinBidIncrementBps(), 500);
        assertEq(s_auction.getMinAuctionDuration(), 15 minutes);
        assertEq(s_auction.getMaxAuctionDuration(), 3 days);
        
        _createAuction();
        assertEq(s_auction.getNextAuctionId(), 1);
    }

    // createAuction tests
    function testCreateAuctionRevertsIfUserIsZeroAddress() public {
        s_collateral.mint(address(s_engine), COLLATERAL_AMOUNT);
        vm.expectRevert(LiquidationAuction.LiquidationAuction__ZeroAddress.selector);
        s_engine.startAuction(address(0), address(s_collateral), COLLATERAL_AMOUNT, TARGET_DEBT, MIN_OPENING_BID, AUCTION_DURATION);
    }

    function testCreateAuctionRevertsIfCollateralTokenIsZeroAddress() public {
        s_collateral.mint(address(s_engine), COLLATERAL_AMOUNT);
        vm.expectRevert(LiquidationAuction.LiquidationAuction__ZeroAddress.selector);
        s_engine.startAuction(USER, address(0), COLLATERAL_AMOUNT, TARGET_DEBT, MIN_OPENING_BID, AUCTION_DURATION);
    }

    function testCreateAuctionRevertsIfCollateralAmountIsZero() public {
        s_collateral.mint(address(s_engine), COLLATERAL_AMOUNT);
        vm.expectRevert(LiquidationAuction.LiquidationAuction__AmountMustBeMoreThanZero.selector);
        s_engine.startAuction(USER, address(s_collateral), 0, TARGET_DEBT, MIN_OPENING_BID, AUCTION_DURATION);
    }

    function testCreateAuctionRevertsIfTargetDebtIsZero() public {
        s_collateral.mint(address(s_engine), COLLATERAL_AMOUNT);
        vm.expectRevert(LiquidationAuction.LiquidationAuction__AmountMustBeMoreThanZero.selector);
        s_engine.startAuction(USER, address(s_collateral), COLLATERAL_AMOUNT, 0, MIN_OPENING_BID, AUCTION_DURATION);
    }

    function testCreateAuctionRevertsIfMinimumBidIsZero() public {
        s_collateral.mint(address(s_engine), COLLATERAL_AMOUNT);
        vm.expectRevert(abi.encodeWithSelector(LiquidationAuction.LiquidationAuction__BidExceedsTargetDebt.selector, 0, TARGET_DEBT));
        s_engine.startAuction(USER, address(s_collateral), COLLATERAL_AMOUNT, TARGET_DEBT, 0, AUCTION_DURATION);
    }

    function testCreateAuctionRevertsIfMinimumBidExceedsTargetDebt() public {
        s_collateral.mint(address(s_engine), COLLATERAL_AMOUNT);
        vm.expectRevert(abi.encodeWithSelector(LiquidationAuction.LiquidationAuction__BidExceedsTargetDebt.selector, TARGET_DEBT + 1, TARGET_DEBT));
        s_engine.startAuction(USER, address(s_collateral), COLLATERAL_AMOUNT, TARGET_DEBT, TARGET_DEBT + 1, AUCTION_DURATION);
    }

    function testCreateAuctionRevertsIfDurationIsTooShort() public {
        s_collateral.mint(address(s_engine), COLLATERAL_AMOUNT);
        uint256 duration = 14 minutes;
        vm.expectRevert(abi.encodeWithSelector(LiquidationAuction.LiquidationAuction__InvalidDuration.selector, duration));
        s_engine.startAuction(USER, address(s_collateral), COLLATERAL_AMOUNT, TARGET_DEBT, MIN_OPENING_BID, duration);
    }

    function testCreateAuctionRevertsIfDurationIsTooLong() public {
        s_collateral.mint(address(s_engine), COLLATERAL_AMOUNT);
        uint256 duration = 3 days + 1 seconds;
        vm.expectRevert(abi.encodeWithSelector(LiquidationAuction.LiquidationAuction__InvalidDuration.selector, duration));
        s_engine.startAuction(USER, address(s_collateral), COLLATERAL_AMOUNT, TARGET_DEBT, MIN_OPENING_BID, duration);
    }

    function _createAuction() internal returns (uint256 auctionId) {
        s_collateral.mint(address(s_engine), COLLATERAL_AMOUNT);
        auctionId = s_engine.startAuction(
            USER, address(s_collateral), COLLATERAL_AMOUNT, TARGET_DEBT, MIN_OPENING_BID, AUCTION_DURATION
        );
    }

    function _mintStableCoinAndApprove(address bidder, uint256 amount) internal {
        s_stableCoin.mint(bidder, amount);
        vm.prank(bidder);
        s_stableCoin.approve(address(s_auction), amount);
    }

    // placeBid tests
    function testPlaceBidRevertsIfAuctionNotFound() public {
        vm.expectRevert(abi.encodeWithSelector(LiquidationAuction.LiquidationAuction__AuctionNotFound.selector, 999));
        s_auction.placeBid(999, MIN_OPENING_BID);
    }

    function testPlaceBidRevertsIfAuctionSettled() public {
        uint256 auctionId = _createAuction();
        _mintStableCoinAndApprove(BIDDER_ONE, TARGET_DEBT);
        
        vm.prank(BIDDER_ONE);
        s_auction.placeBid(auctionId, TARGET_DEBT);
        s_auction.finalizeAuction(auctionId);

        vm.expectRevert(abi.encodeWithSelector(LiquidationAuction.LiquidationAuction__AuctionAlreadySettled.selector, auctionId));
        vm.prank(BIDDER_ONE);
        s_auction.placeBid(auctionId, MIN_OPENING_BID);
    }

    function testPlaceBidRevertsIfBiddingClosed() public {
        uint256 auctionId = _createAuction();
        vm.warp(block.timestamp + AUCTION_DURATION + 1);

        vm.expectRevert(abi.encodeWithSelector(LiquidationAuction.LiquidationAuction__BiddingClosed.selector, auctionId));
        s_auction.placeBid(auctionId, MIN_OPENING_BID);
    }

    function testPlaceBidRevertsIfBidExceedsTargetDebt() public {
        uint256 auctionId = _createAuction();
        uint256 bidAmount = TARGET_DEBT + 1;
        _mintStableCoinAndApprove(BIDDER_ONE, bidAmount);

        vm.expectRevert(abi.encodeWithSelector(LiquidationAuction.LiquidationAuction__BidExceedsTargetDebt.selector, bidAmount, TARGET_DEBT));
        vm.prank(BIDDER_ONE);
        s_auction.placeBid(auctionId, bidAmount);
    }

    function testPlaceBidRevertsIfBidTooLow() public {
        uint256 auctionId = _createAuction();
        uint256 bidAmount = MIN_OPENING_BID - 1;
        _mintStableCoinAndApprove(BIDDER_ONE, bidAmount);

        vm.expectRevert(abi.encodeWithSelector(LiquidationAuction.LiquidationAuction__BidTooLow.selector, MIN_OPENING_BID, bidAmount));
        vm.prank(BIDDER_ONE);
        s_auction.placeBid(auctionId, bidAmount);
    }

    // finalizeAuction tests
    function testFinalizeAuctionRevertsIfAuctionNotFound() public {
        vm.expectRevert(abi.encodeWithSelector(LiquidationAuction.LiquidationAuction__AuctionNotFound.selector, 999));
        s_auction.finalizeAuction(999);
    }

    function testFinalizeAuctionRevertsIfAuctionSettled() public {
        uint256 auctionId = _createAuction();
        _mintStableCoinAndApprove(BIDDER_ONE, TARGET_DEBT);
        
        vm.prank(BIDDER_ONE);
        s_auction.placeBid(auctionId, TARGET_DEBT);
        s_auction.finalizeAuction(auctionId);

        vm.expectRevert(abi.encodeWithSelector(LiquidationAuction.LiquidationAuction__AuctionAlreadySettled.selector, auctionId));
        s_auction.finalizeAuction(auctionId);
    }

    function testFinalizeAuctionRevertsIfAuctionStillRunning() public {
        uint256 auctionId = _createAuction();
        
        vm.expectRevert(abi.encodeWithSelector(LiquidationAuction.LiquidationAuction__AuctionStillRunning.selector, auctionId, block.timestamp + AUCTION_DURATION));
        s_auction.finalizeAuction(auctionId);
    }

    // Transfer failure tests
    function testPlaceBidRevertsIfTransferFails() public {
        uint256 auctionId = _createAuction();
        
        // Mock transferFrom to return false
        vm.mockCall(
            address(s_stableCoin),
            abi.encodeWithSelector(IERC20.transferFrom.selector, BIDDER_ONE, address(s_auction), MIN_OPENING_BID),
            abi.encode(false)
        );
        
        _mintStableCoinAndApprove(BIDDER_ONE, MIN_OPENING_BID);
        
        vm.expectRevert(LiquidationAuction.LiquidationAuction__TransferFailed.selector);
        vm.prank(BIDDER_ONE);
        s_auction.placeBid(auctionId, MIN_OPENING_BID);
    }

    function testFinalizeAuctionRevertsIfStableCoinTransferFails() public {
        uint256 auctionId = _createAuction();
        _mintStableCoinAndApprove(BIDDER_ONE, TARGET_DEBT);
        vm.prank(BIDDER_ONE);
        s_auction.placeBid(auctionId, TARGET_DEBT);
        
        // Mock transfer to return false
        vm.mockCall(
            address(s_stableCoin),
            abi.encodeWithSelector(IERC20.transfer.selector, address(s_engine), TARGET_DEBT),
            abi.encode(false)
        );
        
        vm.expectRevert(LiquidationAuction.LiquidationAuction__TransferFailed.selector);
        s_auction.finalizeAuction(auctionId);
    }

    function testFinalizeAuctionRevertsIfCollateralTransferToWinnerFails() public {
        uint256 auctionId = _createAuction();
        _mintStableCoinAndApprove(BIDDER_ONE, TARGET_DEBT);
        vm.prank(BIDDER_ONE);
        s_auction.placeBid(auctionId, TARGET_DEBT);
        
        // Mock transfer to return false
        // Collateral awarded is full amount since bid == target debt
        vm.mockCall(
            address(s_collateral),
            abi.encodeWithSelector(IERC20.transfer.selector, BIDDER_ONE, COLLATERAL_AMOUNT),
            abi.encode(false)
        );
        
        vm.expectRevert(LiquidationAuction.LiquidationAuction__TransferFailed.selector);
        s_auction.finalizeAuction(auctionId);
    }

    function testFinalizeAuctionRevertsIfCollateralTransferToEngineFails() public {
        uint256 auctionId = _createAuction();
        
        vm.warp(block.timestamp + AUCTION_DURATION + 1);
        
        // Mock transfer to return false
        vm.mockCall(
            address(s_collateral),
            abi.encodeWithSelector(IERC20.transfer.selector, address(s_engine), COLLATERAL_AMOUNT),
            abi.encode(false)
        );
        
        vm.expectRevert(LiquidationAuction.LiquidationAuction__TransferFailed.selector);
        s_auction.finalizeAuction(auctionId);
    }
}
