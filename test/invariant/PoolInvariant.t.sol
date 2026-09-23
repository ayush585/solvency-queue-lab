// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {Pool} from "../../src/Pool.sol";
import {MockERC20} from "../../src/mocks/MockERC20.sol";
import {FeeOnTransferToken} from "../../src/mocks/FeeOnTransferToken.sol";
import {PoolHandler} from "./PoolHandler.sol";

contract PoolInvariantTest is StdInvariant, Test {
    Pool internal pool;
    MockERC20 internal standard;
    FeeOnTransferToken internal feeToken;
    PoolHandler internal handler;

    function setUp() public {
        pool = new Pool();
        standard = new MockERC20("Standard", "STD");
        feeToken = new FeeOnTransferToken(500); // 5%

        address[] memory actors = new address[](4);
        actors[0] = makeAddr("alice");
        actors[1] = makeAddr("bob");
        actors[2] = makeAddr("carol");
        actors[3] = makeAddr("dave");

        handler = new PoolHandler(pool, standard, feeToken, actors);

        bytes4[] memory selectors = new bytes4[](4);
        selectors[0] = PoolHandler.depositStandard.selector;
        selectors[1] = PoolHandler.depositFeeToken.selector;
        selectors[2] = PoolHandler.withdrawStandard.selector;
        selectors[3] = PoolHandler.withdrawFeeToken.selector;

        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    function invariant_standardLiabilitiesNeverExceedAssets() public view {
        assertLe(
            pool.totalLiabilities(address(standard)),
            standard.balanceOf(address(pool)),
            "standard-token liabilities exceed backing assets"
        );
    }

    function invariant_feeTokenLiabilitiesNeverExceedAssets() public view {
        assertLe(
            pool.totalLiabilities(address(feeToken)),
            feeToken.balanceOf(address(pool)),
            "fee-token liabilities exceed backing assets"
        );
    }

    function invariant_closedSystemAccountingMatchesBacking() public view {
        assertEq(pool.totalLiabilities(address(standard)), standard.balanceOf(address(pool)));
        assertEq(pool.totalLiabilities(address(feeToken)), feeToken.balanceOf(address(pool)));
    }
}
