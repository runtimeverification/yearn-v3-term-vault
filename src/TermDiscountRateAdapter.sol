// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import {ITermDiscountRateAdapter} from "./interfaces/term/ITermDiscountRateAdapter.sol";
import {ITermController, AuctionMetadata} from "./interfaces/term/ITermController.sol";
import {ITermRepoToken} from "./interfaces/term/ITermRepoToken.sol";
import "@openzeppelin/contracts-upgradeable/contracts/access/AccessControlUpgradeable.sol";

/**
 * @title TermDiscountRateAdapter
 * @notice Adapter contract to retrieve discount rates for Term repo tokens
 * @dev This contract implements the ITermDiscountRateAdapter interface and interacts with the Term Controller
 */
contract TermDiscountRateAdapter is ITermDiscountRateAdapter, AccessControlUpgradeable {
    bytes32 public constant DEVOPS_ROLE = bytes32(keccak256("DEVOPS_ROLE"));

    /// @notice The Term Controller contract
    ITermController public immutable TERM_CONTROLLER;
    mapping(address => mapping (bytes32 => bool)) public rateInvalid;

    /**
     * @notice Constructor to initialize the TermDiscountRateAdapter
     * @param termController_ The address of the Term Controller contract
     */
    constructor(address termController_, address devopsWallet_) {
        TERM_CONTROLLER = ITermController(termController_);
        _grantRole(DEVOPS_ROLE, devopsWallet_);
    }

    /**
     * @notice Retrieves the discount rate for a given repo token
     * @param repoToken The address of the repo token
     * @return The discount rate for the specified repo token
     * @dev This function fetches the auction results for the repo token's term repo ID
     * and returns the clearing rate of the most recent auction
     */
    function getDiscountRate(address repoToken) external view returns (uint256) {
        (AuctionMetadata[] memory auctionMetadata, ) = TERM_CONTROLLER.getTermAuctionResults(ITermRepoToken(repoToken).termRepoId());

        uint256 len = auctionMetadata.length;
        require(len > 0, "No auctions found");

        if (len > 1) {
            if ((block.timestamp - auctionMetadata[len - 1].auctionClearingBlockTimestamp) < 30 minutes) {
                uint256 i = 0;
                while (!rateInvalid[repoToken][auctionMetadata[len - 1].termAuctionId]) {
                    i--;
                    require(i >= 0, "No valid auction rate found");
                }
                return auctionMetadata[i].auctionClearingRate;
            }
        }

        require(!rateInvalid[repoToken][auctionMetadata[0].termAuctionId], "Most recent auction rate is invalid");

        return auctionMetadata[0].auctionClearingRate;
    }

    function markRateInvalid(address repoToken, bytes32 termAuctionId) external onlyRole(DEVOPS_ROLE) {
        rateInvalid[repoToken][termAuctionId] = true;
    }
}
