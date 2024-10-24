// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

interface ITermDiscountRateAdapter {
    function getDiscountRate(address repoToken) external view returns (uint256);
}
