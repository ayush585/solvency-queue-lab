// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {MockPriceFeed} from "../src/mocks/MockPriceFeed.sol";
import {OracleGuard} from "../src/OracleGuard.sol";
import {OracleMarginBook} from "../src/OracleMarginBook.sol";

contract OracleMarginBookTest is Test {
    MockPriceFeed internal feed;
    OracleGuard internal guard;
    OracleMarginBook internal book;

    address internal alice = makeAddr("alice");

    function setUp() public {
        vm.warp(1_000_000);

        feed = new MockPriceFeed();
        guard = new OracleGuard(feed, 60);
        book = new OracleMarginBook(guard, 1_000, 500);

        feed.setPrice(1_000 ether, block.timestamp);
    }

    function test_positionEntryUsesValidatedOraclePrice() public {
        vm.prank(alice);
        book.openPosition(10_000 ether, 1_000 ether);

        (int256 sizeUsd, uint256 entryPrice, uint256 collateralUsd, bool open) =
            book.positions(alice);

        assertEq(sizeUsd, 10_000 ether);
        assertEq(entryPrice, 1_000 ether);
        assertEq(collateralUsd, 1_000 ether);
        assertTrue(open);
    }

    function test_zeroPriceIsRejected() public {
        feed.setPrice(0, block.timestamp);

        vm.prank(alice);
        vm.expectRevert(OracleGuard.InvalidPrice.selector);
        book.openPosition(10_000 ether, 1_000 ether);
    }

    function test_missingTimestampIsRejected() public {
        feed.setPrice(1_000 ether, 0);

        vm.prank(alice);
        vm.expectRevert(OracleGuard.MissingTimestamp.selector);
        book.openPosition(10_000 ether, 1_000 ether);
    }

    function test_futureTimestampIsRejected() public {
        feed.setPrice(1_000 ether, block.timestamp + 1);

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                OracleGuard.FutureTimestamp.selector,
                block.timestamp + 1,
                block.timestamp
            )
        );
        book.openPosition(10_000 ether, 1_000 ether);
    }

    function test_exactMaxAgeIsAccepted() public {
        feed.setPrice(1_000 ether, block.timestamp - 60);

        vm.prank(alice);
        book.openPosition(10_000 ether, 1_000 ether);

        (,,, bool open) = book.positions(alice);
        assertTrue(open);
    }

    function test_oneSecondPastMaxAgeIsRejected() public {
        uint256 updatedAt = block.timestamp - 61;
        feed.setPrice(1_000 ether, updatedAt);

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                OracleGuard.StalePrice.selector,
                updatedAt,
                block.timestamp,
                60
            )
        );
        book.openPosition(10_000 ether, 1_000 ether);
    }

    function test_staleOracleBlocksLiquidationAndPreservesPosition() public {
        vm.prank(alice);
        book.openPosition(10_000 ether, 1_000 ether);

        vm.warp(block.timestamp + 61);
        feed.setPrice(950 ether, block.timestamp - 61);

        vm.expectRevert();
        book.liquidate(alice);

        (,,, bool open) = book.positions(alice);
        assertTrue(open);
    }

    function test_freshOracleAllowsExactBoundaryLiquidation() public {
        vm.prank(alice);
        book.openPosition(10_000 ether, 1_000 ether);

        feed.setPrice(950 ether, block.timestamp);

        (int256 accountEquity, uint256 maintenance) = book.liquidate(alice);

        assertEq(accountEquity, 500 ether);
        assertEq(maintenance, 500 ether);

        (,,, bool open) = book.positions(alice);
        assertFalse(open);
    }

    function testFuzz_freshnessBoundary(uint32 rawAge) public {
        uint256 age = bound(uint256(rawAge), 0, 120);
        uint256 updatedAt = block.timestamp - age;
        feed.setPrice(1_000 ether, updatedAt);

        if (age <= 60) {
            assertEq(guard.validatedPrice(), 1_000 ether);
        } else {
            vm.expectRevert(
                abi.encodeWithSelector(
                    OracleGuard.StalePrice.selector,
                    updatedAt,
                    block.timestamp,
                    60
                )
            );
            guard.validatedPrice();
        }
    }
}
