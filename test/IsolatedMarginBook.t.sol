// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {IsolatedMarginBook} from "../src/IsolatedMarginBook.sol";

contract IsolatedMarginBookTest is Test {
    uint256 internal constant INITIAL_BPS = 1_000; // 10%
    uint256 internal constant MAINTENANCE_BPS = 500; // 5%

    IsolatedMarginBook internal book;

    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    function setUp() public {
        book = new IsolatedMarginBook(INITIAL_BPS, MAINTENANCE_BPS);
    }

    function test_longLinearPnlMatchesPriceMove() public {
        _open(alice, 10_000 ether, 2_000 ether, 1_000 ether);

        assertEq(book.unrealizedPnl(alice, 2_200 ether), 1_000 ether);
        assertEq(book.equity(alice, 2_200 ether), 2_000 ether);
    }

    function test_shortLinearPnlMatchesPriceMove() public {
        _open(alice, -10_000 ether, 2_000 ether, 1_000 ether);

        assertEq(book.unrealizedPnl(alice, 1_800 ether), 1_000 ether);
        assertEq(book.equity(alice, 1_800 ether), 2_000 ether);
    }

    function test_longAndShortPnlAreSymmetric() public {
        _open(alice, 10_000 ether, 2_000 ether, 1_000 ether);
        _open(bob, -10_000 ether, 2_000 ether, 1_000 ether);

        int256 longPnl = book.unrealizedPnl(alice, 2_200 ether);
        int256 shortPnl = book.unrealizedPnl(bob, 2_200 ether);

        assertEq(longPnl, -shortPnl);
    }

    function test_exactMaintenanceBoundaryIsLiquidatable() public {
        _open(alice, 10_000 ether, 1_000 ether, 1_000 ether);

        assertFalse(book.isLiquidatable(alice, 951 ether));

        assertEq(book.unrealizedPnl(alice, 950 ether), -500 ether);
        assertEq(book.equity(alice, 950 ether), 500 ether);
        assertEq(book.maintenanceMarginRequirement(alice), 500 ether);
        assertTrue(book.isLiquidatable(alice, 950 ether));
    }

    function test_liquidationClosesPositionAtMaintenanceBoundary() public {
        _open(alice, 10_000 ether, 1_000 ether, 1_000 ether);

        (int256 accountEquity, uint256 maintenance) = book.liquidate(alice, 950 ether);

        assertEq(accountEquity, 500 ether);
        assertEq(maintenance, 500 ether);

        (,,, bool open) = book.positions(alice);
        assertFalse(open);

        vm.expectRevert(IsolatedMarginBook.PositionNotOpen.selector);
        book.equity(alice, 950 ether);
    }

    function test_healthyPositionCannotBeLiquidated() public {
        _open(alice, 10_000 ether, 1_000 ether, 1_000 ether);

        vm.expectRevert(
            abi.encodeWithSelector(
                IsolatedMarginBook.NotLiquidatable.selector, int256(510 ether), 500 ether
            )
        );
        book.liquidate(alice, 951 ether);
    }

    function test_openBelowInitialMarginIsRejected() public {
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                IsolatedMarginBook.InitialMarginTooLow.selector, 1_000 ether, 999 ether
            )
        );
        book.openPosition(10_000 ether, 1_000 ether, 999 ether);
    }

    function test_removingCollateralCannotBreakInitialMargin() public {
        _open(alice, 10_000 ether, 1_000 ether, 1_000 ether);

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                IsolatedMarginBook.CollateralRemovalUnsafe.selector, int256(999 ether), 1_000 ether
            )
        );
        book.removeCollateral(1 ether, 1_000 ether);
    }

    function test_addingCollateralCanRescueLiquidatablePosition() public {
        _open(alice, 10_000 ether, 1_000 ether, 1_000 ether);

        assertTrue(book.isLiquidatable(alice, 940 ether));

        vm.prank(alice);
        book.addCollateral(200 ether);

        assertFalse(book.isLiquidatable(alice, 940 ether));
        assertEq(book.equity(alice, 940 ether), 600 ether);
    }

    function test_oversizedPositionIsRejectedAtOpen() public {
        vm.prank(alice);
        vm.expectRevert(IsolatedMarginBook.RiskInputTooLarge.selector);
        book.openPosition(int256(1e36 + 1), 1_000 ether, 1e36);
    }

    function testFuzz_longShortPnlSymmetry(uint128 rawSize, uint128 rawEntry, uint128 rawMark)
        public
    {
        uint256 size = bound(uint256(rawSize), 100 ether, 1e30);
        uint256 entry = bound(uint256(rawEntry), 1 ether, 1e24);
        uint256 mark = bound(uint256(rawMark), 1 ether, 1e24);

        _open(alice, int256(size), entry, size);
        _open(bob, -int256(size), entry, size);

        assertEq(book.unrealizedPnl(alice, mark), -book.unrealizedPnl(bob, mark));
    }

    function testFuzz_pnlIsZeroAtEntry(uint128 rawSize, uint128 rawEntry) public {
        uint256 size = bound(uint256(rawSize), 100 ether, 1e30);
        uint256 entry = bound(uint256(rawEntry), 1 ether, 1e24);

        _open(alice, int256(size), entry, size);

        assertEq(book.unrealizedPnl(alice, entry), 0);
        assertEq(book.equity(alice, entry), int256(size));
    }

    function _open(address account, int256 sizeUsd, uint256 entryPrice, uint256 collateralUsd)
        internal
    {
        vm.prank(account);
        book.openPosition(sizeUsd, entryPrice, collateralUsd);
    }
}
