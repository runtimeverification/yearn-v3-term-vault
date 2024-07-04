pragma solidity ^0.8.18;

import "forge-std/console.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";
import {MockTermRepoToken} from "./mocks/MockTermRepoToken.sol";
import {MockTermAuction} from "./mocks/MockTermAuction.sol";
import {MockUSDC} from "./mocks/MockUSDC.sol";
import {Setup, ERC20, IStrategyInterface} from "./utils/Setup.sol";
import {Strategy} from "../Strategy.sol";

contract TestUSDCSubmitOffer is Setup {
    uint256 internal constant TEST_REPO_TOKEN_RATE = 0.05e18;

    MockUSDC internal mockUSDC;
    ERC20Mock internal mockCollateral; 
    MockTermRepoToken internal repoToken1Week;
    MockTermAuction internal repoToken1WeekAuction;
    Strategy internal termStrategy;
    StrategySnapshot internal initialState;

    function setUp() public override {
        mockUSDC = new MockUSDC();
        mockCollateral = new ERC20Mock();

        _setUp(ERC20(address(mockUSDC)));

        repoToken1Week = new MockTermRepoToken(
            bytes32("test repo token 1"), address(mockUSDC), address(mockCollateral), 1e18, 1 weeks
        );        
        termController.setOracleRate(MockTermRepoToken(repoToken1Week).termRepoId(), TEST_REPO_TOKEN_RATE);

        termStrategy = Strategy(address(strategy));

        repoToken1WeekAuction = new MockTermAuction(repoToken1Week);

        vm.startPrank(management);
        termStrategy.setCollateralTokenParams(address(mockCollateral), 0.5e18);
        termStrategy.setTimeToMaturityThreshold(3 weeks);
        vm.stopPrank();

        // start with some initial funds
        mockUSDC.mint(address(strategy), 100e6);

        initialState.totalAssetValue = termStrategy.totalAssetValue();
        initialState.totalLiquidBalance = termStrategy.totalLiquidBalance();
    }

    function _submitOffer(bytes32 offerId, uint256 offerAmount) private { 
        // test: only management can submit offers
        vm.expectRevert("!management");
        bytes32[] memory offerIds = termStrategy.submitAuctionOffer(
            address(repoToken1WeekAuction), address(repoToken1Week), offerId, bytes32("test price"), offerAmount
        );        

        vm.prank(management);
        offerIds = termStrategy.submitAuctionOffer(
            address(repoToken1WeekAuction), address(repoToken1Week), offerId, bytes32("test price"), offerAmount
        );        

        assertEq(offerIds.length, 1);
        assertEq(offerIds[0], offerId);
    }

    function testSubmitOffer() public {       
        _submitOffer(bytes32("offer id 1"), 1e6);

        assertEq(termStrategy.totalLiquidBalance(), initialState.totalLiquidBalance - 1e6);
        // test: totalAssetValue = total liquid balance + pending offer amount
        assertEq(termStrategy.totalAssetValue(), termStrategy.totalLiquidBalance() + 1e6);
    }

    function testEditOffer() public {
        _submitOffer(bytes32("offer id 1"), 1e6);

        // TODO: fuzz this
        uint256 offerAmount = 4e6;

        vm.prank(management);
        bytes32[] memory offerIds = termStrategy.submitAuctionOffer(
            address(repoToken1WeekAuction), address(repoToken1Week), bytes32("offer id 1"), bytes32("test price"), offerAmount
        );        

        assertEq(termStrategy.totalLiquidBalance(), initialState.totalLiquidBalance - offerAmount);
        // test: totalAssetValue = total liquid balance + pending offer amount
        assertEq(termStrategy.totalAssetValue(), termStrategy.totalLiquidBalance() + offerAmount);
    }

    function testDeleteOffers() public {
        _submitOffer(bytes32("offer id 1"), 1e6);

        bytes32[] memory offerIds = new bytes32[](1);

        offerIds[0] = bytes32("offer id 1");

        vm.expectRevert("!management");
        termStrategy.deleteAuctionOffers(address(repoToken1WeekAuction), offerIds);

        vm.prank(management);
        termStrategy.deleteAuctionOffers(address(repoToken1WeekAuction), offerIds);

        assertEq(termStrategy.totalLiquidBalance(), initialState.totalLiquidBalance);
        assertEq(termStrategy.totalAssetValue(), termStrategy.totalLiquidBalance());
    }

    uint256 public constant THREESIXTY_DAYCOUNT_SECONDS = 360 days;
    uint256 public constant RATE_PRECISION = 1e18;
    
    function _getRepoTokenAmountGivenPurchaseTokenAmount(
        uint256 purchaseTokenAmount,
        MockTermRepoToken termRepoToken,
        uint256 auctionRate
    ) private view returns (uint256) {
        (uint256 redemptionTimestamp, address purchaseToken, ,) = termRepoToken.config();

        uint256 purchaseTokenPrecision = 10**ERC20(purchaseToken).decimals();
        uint256 repoTokenPrecision = 10**ERC20(address(termRepoToken)).decimals();

        uint256 timeLeftToMaturityDayFraction = 
            ((redemptionTimestamp - block.timestamp) * purchaseTokenPrecision) / THREESIXTY_DAYCOUNT_SECONDS;

        // purchaseTokenAmount * (1 + r * days / 360) = repoTokenAmountInBaseAssetPrecision
        uint256 repoTokenAmountInBaseAssetPrecision = 
            purchaseTokenAmount * (purchaseTokenPrecision + (auctionRate * timeLeftToMaturityDayFraction / RATE_PRECISION)) / purchaseTokenPrecision;

        return repoTokenAmountInBaseAssetPrecision * repoTokenPrecision / purchaseTokenPrecision;
    }

    function testCompleteAuctionSuccessFull() public {
        _submitOffer(bytes32("offer id 1"), 1e6);

        bytes32[] memory offerIds = new bytes32[](1);
        offerIds[0] = bytes32("offer id 1");
        uint256[] memory fillAmounts = new uint256[](1);
        fillAmounts[0] = 1e6;
        uint256[] memory repoTokenAmounts = new uint256[](1);
        repoTokenAmounts[0] = _getRepoTokenAmountGivenPurchaseTokenAmount(
            1e6, repoToken1Week, TEST_REPO_TOKEN_RATE
        );

        repoToken1WeekAuction.auctionSuccess(offerIds, fillAmounts, repoTokenAmounts);

        // test: asset value should equal to initial asset value (liquid + pending offers)
        assertEq(termStrategy.totalAssetValue(), initialState.totalAssetValue);

        address[] memory holdings = termStrategy.repoTokenHoldings();

        // test: 0 holding because auctionClosed not yet called
        assertEq(holdings.length, 0);

        termStrategy.auctionClosed();

        // test: asset value should equal to initial asset value (liquid + repo tokens)
        assertEq(termStrategy.totalAssetValue(), initialState.totalAssetValue);

        holdings = termStrategy.repoTokenHoldings();

        // test: check repo token holdings
        assertEq(holdings.length, 1);
        assertEq(holdings[0], address(repoToken1Week));

        bytes32[] memory offers = termStrategy.pendingOffers();        

        assertEq(offers.length, 0);
    }

    function testCompleteAuctionSuccessPartial() public {
        _submitOffer(bytes32("offer id 1"), 1e6);

        bytes32[] memory offerIds = new bytes32[](1);
        offerIds[0] = bytes32("offer id 1");
        uint256[] memory fillAmounts = new uint256[](1);

        // test: 50% filled
        fillAmounts[0] = 0.5e6;
        uint256[] memory repoTokenAmounts = new uint256[](1);
        repoTokenAmounts[0] = _getRepoTokenAmountGivenPurchaseTokenAmount(
            0.5e6, repoToken1Week, TEST_REPO_TOKEN_RATE
        );

        repoToken1WeekAuction.auctionSuccess(offerIds, fillAmounts, repoTokenAmounts);

        // test: asset value should equal to initial asset value (liquid + pending offers)
        assertEq(termStrategy.totalAssetValue(), initialState.totalAssetValue);

        address[] memory holdings = termStrategy.repoTokenHoldings();

        // test: 0 holding because auctionClosed not yet called
        assertEq(holdings.length, 0);

        termStrategy.auctionClosed();

        // test: asset value should equal to initial asset value (liquid + repo tokens)
        assertEq(termStrategy.totalAssetValue(), initialState.totalAssetValue);

        holdings = termStrategy.repoTokenHoldings();

        // test: check repo token holdings
        assertEq(holdings.length, 1);
        assertEq(holdings[0], address(repoToken1Week));

        bytes32[] memory offers = termStrategy.pendingOffers();        

        assertEq(offers.length, 0);
    }

    function testCompleteAuctionCanceled() public {
        _submitOffer(bytes32("offer id 1"), 1e6);

        repoToken1WeekAuction.auctionCanceled();    

        // test: check value before calling complete auction
        termStrategy.auctionClosed();

        bytes32[] memory offers = termStrategy.pendingOffers();

        assertEq(offers.length, 0);
    }

    function testMultipleOffers() public {
        _submitOffer(bytes32("offer id 1"), 1e6);
        _submitOffer(bytes32("offer id 2"), 5e6);

        assertEq(termStrategy.totalLiquidBalance(), initialState.totalLiquidBalance - 6e6);
        // test: totalAssetValue = total liquid balance + pending offer amount
        assertEq(termStrategy.totalAssetValue(), termStrategy.totalLiquidBalance() + 6e6);

        bytes32[] memory offers = termStrategy.pendingOffers();

        assertEq(offers.length, 2);
        assertEq(offers[0], bytes32("offer id 2"));
        assertEq(offers[1], bytes32("offer id 1"));
    }
}