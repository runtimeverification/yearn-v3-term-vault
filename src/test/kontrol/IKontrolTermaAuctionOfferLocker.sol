// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import "src/interfaces/term/ITermAuctionOfferLocker.sol";

interface IKontrolTermAuctionOfferLocker is ITermAuctionOfferLocker {

    function lockedOfferAmount(bytes32 id) external view returns (uint256);
}