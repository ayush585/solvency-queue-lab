// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {Pool} from "../../src/Pool.sol";
import {MockERC20} from "../../src/mocks/MockERC20.sol";
import {FeeOnTransferToken} from "../../src/mocks/FeeOnTransferToken.sol";

contract PoolHandler is Test {
    Pool public immutable pool;
    MockERC20 public immutable standard;
    FeeOnTransferToken public immutable feeToken;

    address[] internal actors;

    constructor(
        Pool pool_,
        MockERC20 standard_,
        FeeOnTransferToken feeToken_,
        address[] memory actors_
    ) {
        pool = pool_;
        standard = standard_;
        feeToken = feeToken_;
        actors = actors_;
    }

    function depositStandard(uint256 actorSeed, uint96 rawAmount) external {
        address actor = _actor(actorSeed);
        uint256 amount = bound(uint256(rawAmount), 1, 1_000 ether);

        standard.mint(actor, amount);
        vm.startPrank(actor);
        standard.approve(address(pool), amount);
        pool.deposit(address(standard), amount);
        vm.stopPrank();
    }

    function depositFeeToken(uint256 actorSeed, uint96 rawAmount) external {
        address actor = _actor(actorSeed);
        uint256 amount = bound(uint256(rawAmount), 10_000, 1_000 ether);

        feeToken.mint(actor, amount);
        vm.startPrank(actor);
        feeToken.approve(address(pool), amount);
        pool.deposit(address(feeToken), amount);
        vm.stopPrank();
    }

    function withdrawStandard(uint256 actorSeed, uint96 rawAmount) external {
        address actor = _actor(actorSeed);
        uint256 claim = pool.balanceOf(address(standard), actor);
        if (claim == 0) return;

        uint256 amount = bound(uint256(rawAmount), 1, claim);
        vm.prank(actor);
        pool.withdraw(address(standard), amount);
    }

    function withdrawFeeToken(uint256 actorSeed, uint96 rawAmount) external {
        address actor = _actor(actorSeed);
        uint256 claim = pool.balanceOf(address(feeToken), actor);
        if (claim == 0) return;

        uint256 amount = bound(uint256(rawAmount), 1, claim);

        // Fee-on-transfer withdrawals are intentionally unsupported. A failed attempt
        // must leave both the user's claim and the pool's asset backing unchanged.
        vm.prank(actor);
        try pool.withdraw(address(feeToken), amount) {} catch {}
    }

    function _actor(uint256 seed) internal view returns (address) {
        return actors[seed % actors.length];
    }
}
