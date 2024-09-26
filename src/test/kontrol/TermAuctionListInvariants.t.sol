pragma solidity 0.8.23;

import "forge-std/Vm.sol";
import "forge-std/Test.sol";
import "kontrol-cheatcodes/KontrolCheats.sol";

import "src/RepoTokenList.sol";
import "src/TermAuctionList.sol";

import "src/test/kontrol/Constants.sol";
import "src/test/kontrol/RepoToken.sol";
import "src/test/kontrol/RepoTokenListInvariants.t.sol";
import "src/test/kontrol/TermAuction.sol";
import "src/test/kontrol/TermAuctionOfferLocker.sol";
import "src/test/kontrol/TermDiscountRateAdapter.sol";

contract TermAuctionListInvariantsTest is RepoTokenListInvariantsTest {
    using TermAuctionList for TermAuctionListData;

    TermAuctionListData _termAuctionList;

    /**
     * Return the auction for a given offer in the list.
     */
    function _getAuction(bytes32 offerId) internal returns(address) {
        return address(_termAuctionList.offers[offerId].termAuction);
    }

    /**
     * Initialize _termAuctionList to a TermAuctionList of arbitrary size,
     * comprised of offers with distinct ids.
     */
    function _initializeTermAuctionList() internal {
        bytes32 previous = TermAuctionList.NULL_NODE;
        uint256 count = 0;

        while (kevm.freshBool() != 0) {
            TermAuctionOfferLocker offerLocker = new TermAuctionOfferLocker();
            bytes32 current = keccak256(
                abi.encodePacked(count, address(this), address(offerLocker))
            );
            offerLocker.initializeSymbolic(current);

            if (previous == TermAuctionList.NULL_NODE) {
                _termAuctionList.head = current;
            } else {
                _termAuctionList.nodes[previous].next = current;
            }

            // TODO: Auction must be symbolic to ensure sortedness assumption,
            // but it needs to be callable. Can we etch a symbolic variable?
            PendingOffer storage offer = _termAuctionList.offers[current];
            offer.repoToken = kevm.freshAddress();
            offer.offerAmount = freshUInt256();
            offer.termAuction = ITermAuction(kevm.freshAddress());
            offer.offerLocker = offerLocker;

            previous = current;
            ++count;
        }

        if (previous == TermAuctionList.NULL_NODE) {
            _termAuctionList.head = TermAuctionList.NULL_NODE;
        } else {
            _termAuctionList.nodes[previous].next = TermAuctionList.NULL_NODE;
        }
    }

    /**
     * Initialize the TermDiscountRateAdapter to a symbolic state.
     */
    function _initializeDiscountRateAdapter(
        TermDiscountRateAdapter discountRateAdapter
    ) internal {
        discountRateAdapter.initializeSymbolic();

        address current = _repoTokenList.head;

        while (current != RepoTokenList.NULL_NODE) {
            discountRateAdapter.initializeSymbolicFor(current);

            current = _repoTokenList.nodes[current].next;
        }
    }

    /**
     * Assume or assert that the offers in the list are sorted by auction.
     */
    function _establishSortedByAuctionId(Mode mode) internal {
        bytes32 previous = TermAuctionList.NULL_NODE;
        bytes32 current = _termAuctionList.head;

        while (current != TermAuctionList.NULL_NODE) {
            if (previous != TermAuctionList.NULL_NODE) {
                address previousAuction = _getAuction(current);
                address currentAuction = _getAuction(current);
                _establish(mode, previousAuction <= currentAuction);
            }

            previous = current;
            current = _termAuctionList.nodes[current].next;
        }
    }

    /**
     * Assume or assert that there are no duplicate offers in the list.
     */
    function _establishNoDuplicateOffers(Mode mode) internal {
        bytes32 current = _termAuctionList.head;

        while (current != TermAuctionList.NULL_NODE) {
            bytes32 other = _termAuctionList.nodes[current].next;

            while (other != TermAuctionList.NULL_NODE) {
                _establish(mode, current != other);
                other = _termAuctionList.nodes[other].next;
            }

            current = _termAuctionList.nodes[current].next;
        }
    }

    /**
     * Assume or assert that there are no completed auctions in the list.
     */
    function _establishNoCompletedAuctions(Mode mode) internal {
        bytes32 current = _termAuctionList.head;

        while (current != TermAuctionList.NULL_NODE) {
            PendingOffer memory offer = _termAuctionList.offers[current];
            _establish(mode, !offer.termAuction.auctionCompleted());

            current = _termAuctionList.nodes[current].next;
        }
    }

    /**
     * Assume or assert that all offer amounts are > 0.
     */
    function _establishPositiveOfferAmounts(Mode mode) internal {
        bytes32 current = _termAuctionList.head;

        while (current != TermAuctionList.NULL_NODE) {
            PendingOffer memory offer = _termAuctionList.offers[current];
            _establish(mode, 0 < offer.offerAmount);

            current = _termAuctionList.nodes[current].next;
        }
    }

    /**
     * Assume or assert that the offer amounts recorded in the list are the same
     * as the offer amounts in the offer locker.
     */
    function _establishOfferAmountMatchesAmountLocked(Mode mode) internal {
        bytes32 current = _termAuctionList.head;

        while (current != TermAuctionList.NULL_NODE) {
            PendingOffer memory offer = _termAuctionList.offers[current];
            uint256 offerAmount = offer.offerLocker.lockedOffer(current).amount;
            _establish(mode, offer.offerAmount == offerAmount);

            current = _termAuctionList.nodes[current].next;
        }
    }

    /**
     * Count the number of offers in the list.
     *
     * Note that this function guarantees the following postconditions:
     * - The head of the list is NULL_NODE iff the count is 0.
     * - If the count is N, the Nth node in the list is followed by NULL_NODE.
     */
    function _countOffersInList() internal returns (uint256) {
        uint256 count = 0;
        bytes32 current = _termAuctionList.head;

        while (current != TermAuctionList.NULL_NODE) {
            ++count;
            current = _termAuctionList.nodes[current].next;
        }

        return count;
    }

    /**
     * Return true if the given offer id is in the list, and false otherwise.
     */
    function _offerInList(bytes32 offerId) internal returns (bool) {
        bytes32 current = _termAuctionList.head;

        while (current != TermAuctionList.NULL_NODE) {
            if (current == offerId) {
                return true;
            }

            current = _termAuctionList.nodes[current].next;
        }

        return false;
    }

    /**
     * Test that insertPending preserves the list invariants when a new offer
     * is added (that was not present in the list before).
     */
    function testInsertPendingNewOffer(
        bytes32 offerId,
        PendingOffer memory pendingOffer
    ) external {
        // Initialize TermAuctionList of arbitrary size
        kevm.symbolicStorage(address(this));
        _initializeTermAuctionList();

        // Assume that the invariants hold before the function is called
        _establishSortedByAuctionId(Mode.Assume);
        _establishNoDuplicateOffers(Mode.Assume);
        _establishNoCompletedAuctions(Mode.Assume);
        _establishPositiveOfferAmounts(Mode.Assume);
        _establishOfferAmountMatchesAmountLocked(Mode.Assume);

        // Save the number of offers in the list before the function is called
        uint256 count = _countOffersInList();

        // Assume that the offer is not already in the list
        vm.assume(!_offerInList(offerId));

        // Call the function being tested
        _termAuctionList.insertPending(offerId, pendingOffer);

        // Assert that the size of the list increased by 1
        assertEq(_countOffersInList(), count + 1);

        // Assert that the new offer is in the list
        assertTrue(_offerInList(offerId));

        // Assert that the invariants are preserved
        _establishSortedByAuctionId(Mode.Assert);
        _establishNoDuplicateOffers(Mode.Assert);
        _establishNoCompletedAuctions(Mode.Assert);
        _establishPositiveOfferAmounts(Mode.Assert);
        _establishOfferAmountMatchesAmountLocked(Mode.Assert);
    }

    
    /**
     * Test that insertPending preserves the list invariants when trying to
     * insert an offer that is already in the list.
     */
    function testInsertPendingDuplicateOffer(
        bytes32 offerId,
        PendingOffer memory pendingOffer
    ) external {
        // Initialize TermAuctionList of arbitrary size
        kevm.symbolicStorage(address(this));
        _initializeTermAuctionList();

        // Assume that the invariants hold before the function is called
        _establishSortedByAuctionId(Mode.Assume);
        _establishNoDuplicateOffers(Mode.Assume);
        _establishNoCompletedAuctions(Mode.Assume);
        _establishPositiveOfferAmounts(Mode.Assume);
        _establishOfferAmountMatchesAmountLocked(Mode.Assume);

        // Save the number of offers in the list before the function is called
        uint256 count = _countOffersInList();

        // Assume that the offer is already in the list
        vm.assume(_offerInList(offerId));

        // Call the function being tested
        _termAuctionList.insertPending(offerId, pendingOffer);

        // Assert that the size of the list didn't change
        assertEq(_countOffersInList(), count);

        // Assert that the new offer is in the list
        assertTrue(_offerInList(offerId));

        // Assert that the invariants are preserved
        _establishSortedByAuctionId(Mode.Assert);
        _establishNoDuplicateOffers(Mode.Assert);
        _establishNoCompletedAuctions(Mode.Assert);
        _establishPositiveOfferAmounts(Mode.Assert);
        _establishOfferAmountMatchesAmountLocked(Mode.Assert);
    }

    /**
     * Test that removeCompleted preserves the list invariants.
     */
    function testRemoveCompleted(address asset) external {
        // Initialize RepoTokenList and TermAuctionList of arbitrary size
        kevm.symbolicStorage(address(this));
        _initializeRepoTokenList();
        _initializeTermAuctionList();

        // Initialize a DiscountRateAdapter with symbolic storage
        TermDiscountRateAdapter discountRateAdapter =
            new TermDiscountRateAdapter();
        _initializeDiscountRateAdapter(discountRateAdapter);

        // TODO: Initialize TermAuctions and RepoTokens

        // Assume that the invariants hold before the function is called
        _establishSortedByAuctionId(Mode.Assume);
        _establishNoDuplicateOffers(Mode.Assume);
        _establishOfferAmountMatchesAmountLocked(Mode.Assume);

        // Save the number of tokens in the list before the function is called
        uint256 count = _countOffersInList();

        // Call the function being tested
        _termAuctionList.removeCompleted(
            _repoTokenList,
            discountRateAdapter,
            asset
        );

        // Assert that the size of the list is less than or equal to before
        assertLe(_countOffersInList(), count);

        // Assert that the invariants are preserved
        _establishSortedByAuctionId(Mode.Assert);
        _establishNoDuplicateOffers(Mode.Assert);
        _establishOfferAmountMatchesAmountLocked(Mode.Assert);

        // Now the following invariants should hold as well
        _establishNoCompletedAuctions(Mode.Assert);
        _establishPositiveOfferAmounts(Mode.Assert);

        // TODO: Check RepoTokenList invariants?
    }
}
