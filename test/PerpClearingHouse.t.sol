// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {PerpClearingHouse} from "../src/PerpClearingHouse.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {FeeOnTransferToken} from "../src/mocks/FeeOnTransferToken.sol";

contract PerpClearingHouseTest is Test {
    uint256 internal constant INITIAL_BPS = 1_000; // 10%
    uint256 internal constant MAINTENANCE_BPS = 500; // 5%
    uint256 internal constant LIQUIDATION_FEE_BPS = 100; // 1%

    MockERC20 internal token;
    PerpClearingHouse internal engine;

    address internal alice = makeAddr("alice");
    address internal insuranceFunder = makeAddr("insurance-funder");
    address internal counterparty = makeAddr("counterparty");

    function setUp() public {
        token = new MockERC20("Settlement Token", "SET");
        engine = new PerpClearingHouse(
            address(token), counterparty, INITIAL_BPS, MAINTENANCE_BPS, LIQUIDATION_FEE_BPS
        );
    }

    function test_solventLiquidationSplitsLossFeeAndResidualExactly() public {
        _openLong(alice, 10_000 ether, 1_000 ether, 1_000 ether);

        engine.liquidate(alice, 950 ether);

        assertEq(token.balanceOf(counterparty), 500 ether);
        assertEq(token.balanceOf(alice), 400 ether);
        assertEq(engine.insuranceBalance(), 100 ether);
        assertEq(engine.uncoveredBadDebt(), 0);
        assertEq(engine.totalOpenCollateral(), 0);
        assertEq(token.balanceOf(address(engine)), 100 ether);
        assertEq(engine.accountedAssets(), 100 ether);
    }

    function test_partialInsuranceCoverageLeavesExplicitBadDebt() public {
        _fundInsurance(300 ether);
        _openLong(alice, 10_000 ether, 1_000 ether, 1_000 ether);

        engine.liquidate(alice, 850 ether);

        assertEq(token.balanceOf(counterparty), 1_300 ether);
        assertEq(token.balanceOf(alice), 0);
        assertEq(engine.insuranceBalance(), 0);
        assertEq(engine.uncoveredBadDebt(), 200 ether);
        assertEq(token.balanceOf(address(engine)), 0);
        assertEq(engine.accountedAssets(), 0);
    }

    function test_sufficientInsuranceFullyCoversBankruptcy() public {
        _fundInsurance(700 ether);
        _openLong(alice, 10_000 ether, 1_000 ether, 1_000 ether);

        engine.liquidate(alice, 850 ether);

        assertEq(token.balanceOf(counterparty), 1_500 ether);
        assertEq(engine.insuranceBalance(), 200 ether);
        assertEq(engine.uncoveredBadDebt(), 0);
        assertEq(token.balanceOf(address(engine)), 200 ether);
        assertEq(engine.accountedAssets(), 200 ether);
    }

    function test_liquidationFeeIsCappedByPositiveEquity() public {
        _openLong(alice, 10_000 ether, 1_000 ether, 1_000 ether);

        // PnL = -950, equity = 50. Nominal 1% liquidation fee = 100,
        // so the actual fee must cap at the remaining 50 of equity.
        engine.liquidate(alice, 905 ether);

        assertEq(token.balanceOf(counterparty), 950 ether);
        assertEq(token.balanceOf(alice), 0);
        assertEq(engine.insuranceBalance(), 50 ether);
        assertEq(token.balanceOf(address(engine)), 50 ether);
    }

    function test_healthyPositionCannotBeLiquidated() public {
        _openLong(alice, 10_000 ether, 1_000 ether, 1_000 ether);

        vm.expectRevert(
            abi.encodeWithSelector(
                PerpClearingHouse.NotLiquidatable.selector, int256(510 ether), 500 ether
            )
        );
        engine.liquidate(alice, 951 ether);
    }

    function test_insuranceFundingIsBackedByRealTokens() public {
        _fundInsurance(500 ether);

        assertEq(engine.insuranceBalance(), 500 ether);
        assertEq(token.balanceOf(address(engine)), 500 ether);
        assertEq(engine.accountedAssets(), 500 ether);
    }

    function test_feeOnTransferCollateralIsRejectedAtomically() public {
        FeeOnTransferToken feeToken = new FeeOnTransferToken(1_000);
        PerpClearingHouse feeEngine = new PerpClearingHouse(
            address(feeToken), counterparty, INITIAL_BPS, MAINTENANCE_BPS, LIQUIDATION_FEE_BPS
        );

        feeToken.mint(alice, 1_000 ether);

        vm.startPrank(alice);
        feeToken.approve(address(feeEngine), type(uint256).max);
        vm.expectRevert(
            abi.encodeWithSelector(
                PerpClearingHouse.UnexpectedReceived.selector, 1_000 ether, 900 ether
            )
        );
        feeEngine.openPosition(10_000 ether, 1_000 ether, 1_000 ether);
        vm.stopPrank();

        assertEq(feeToken.balanceOf(alice), 1_000 ether);
        assertEq(feeToken.balanceOf(address(feeEngine)), 0);
        assertEq(feeEngine.totalOpenCollateral(), 0);
    }

    function testFuzz_bankruptcyWaterfallConservesAssets(uint96 rawInsurance, uint16 rawDropBps)
        public
    {
        uint256 insurance = bound(uint256(rawInsurance), 0, 2_000 ether);
        uint256 dropBps = bound(uint256(rawDropBps), 1_001, 5_000);

        if (insurance != 0) _fundInsurance(insurance);
        _openLong(alice, 10_000 ether, 1_000 ether, 1_000 ether);

        uint256 markPrice = (1_000 ether * (10_000 - dropBps)) / 10_000;
        if (!engine.isLiquidatable(alice, markPrice)) return;

        uint256 supplyBefore = token.totalSupply();

        engine.liquidate(alice, markPrice);

        assertEq(token.totalSupply(), supplyBefore);
        assertEq(
            token.balanceOf(address(engine)),
            engine.totalOpenCollateral() + engine.insuranceBalance()
        );
        assertEq(
            token.balanceOf(address(engine)) + token.balanceOf(counterparty)
                + token.balanceOf(alice),
            supplyBefore
        );
    }

    function _openLong(address account, uint256 sizeUsd, uint256 entryPrice, uint256 collateral)
        internal
    {
        token.mint(account, collateral);

        vm.startPrank(account);
        token.approve(address(engine), type(uint256).max);
        engine.openPosition(int256(sizeUsd), entryPrice, collateral);
        vm.stopPrank();
    }

    function _fundInsurance(uint256 amount) internal {
        token.mint(insuranceFunder, amount);

        vm.startPrank(insuranceFunder);
        token.approve(address(engine), type(uint256).max);
        engine.fundInsurance(amount);
        vm.stopPrank();
    }
}
