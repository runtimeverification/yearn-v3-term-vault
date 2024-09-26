pragma solidity 0.8.23;

import "forge-std/Test.sol";
import "kontrol-cheatcodes/KontrolCheats.sol";

import "src/interfaces/term/ITermAuctionOfferLocker.sol";

import "src/test/kontrol/Constants.sol";

contract TermAuctionOfferLocker is ITermAuctionOfferLocker, Test, KontrolCheats {
    mapping(bytes32 => TermAuctionOffer) _lockedOffers;

    function initializeSymbolic(bytes32 offerId) public {
        kevm.symbolicStorage(address(this));

        TermAuctionOffer memory offer = _lockedOffers[offerId];

        offer.amount = freshUInt256();
        vm.assume(offer.amount < ETH_UPPER_BOUND);
    }

    function termRepoId() external view returns (bytes32) {
        return bytes32(freshUInt256());
    }

    function termAuctionId() external view returns (bytes32) {
        return bytes32(freshUInt256());
    }

    function auctionStartTime() external view returns (uint256) {
        return freshUInt256();
    }

    function auctionEndTime() external view returns (uint256) {
        return freshUInt256();
    }

    function revealTime() external view returns (uint256) {
        return freshUInt256();
    }

    function purchaseToken() external view returns (address) {
        return kevm.freshAddress();
    }

    function termRepoServicer() external view returns (address) {
        return kevm.freshAddress();
    }

    function lockedOffer(bytes32 id) external view returns (TermAuctionOffer memory) {
        return _lockedOffers[id];
    }

    function lockOffers(
        TermAuctionOfferSubmission[] calldata offerSubmissions
    ) external returns (bytes32[] memory) {
        kevm.symbolicStorage(address(this));

        uint256 length = freshUInt256();
        bytes32[] memory offers = new bytes32[](length);

        for (uint256 i = 0; i < length; ++i) {
            offers[i] = bytes32(freshUInt256());
        }

        return offers;
    }

    function unlockOffers(bytes32[] calldata offerIds) external {
        // Function might revert in some cases
        require(kevm.freshBool() != 0);

        // TODO: Other side effects?

        kevm.symbolicStorage(address(this));
    }
}
