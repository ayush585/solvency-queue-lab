// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {Pool} from "../src/Pool.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {VulnerableWithdrawalManager} from "../src/VulnerableWithdrawalManager.sol";

contract VulnerableWithdrawalManagerTest is Test {
    uint256 internal constant ALICE_PK = 0xA11CE;

    Pool internal pool;
    MockERC20 internal token;
    VulnerableWithdrawalManager internal manager;

    address internal alice;
    address internal recipient = makeAddr("recipient");
    address internal relayer = makeAddr("relayer");

    function setUp() public {
        alice = vm.addr(ALICE_PK);

        pool = new Pool();
        token = new MockERC20("Standard", "STD");
        manager = new VulnerableWithdrawalManager(pool);

        pool.setWithdrawalOperator(address(manager), true);

        token.mint(alice, 500 ether);
        vm.startPrank(alice);
        token.approve(address(pool), type(uint256).max);
        pool.deposit(address(token), 500 ether);
        vm.stopPrank();
    }

    function test_sameSignedWithdrawalCanBeReplayedTwice() public {
        VulnerableWithdrawalManager.Withdrawal memory request =
            VulnerableWithdrawalManager.Withdrawal({
                user: alice,
                token: address(token),
                recipient: recipient,
                amount: 100 ether,
                nonce: 0,
                deadline: block.timestamp + 1 days
            });

        bytes memory signature = _sign(manager.digest(request));

        vm.prank(relayer);
        manager.withdrawWithSig(request, signature);

        vm.prank(relayer);
        manager.withdrawWithSig(request, signature);

        assertEq(token.balanceOf(recipient), 200 ether);
        assertEq(pool.balanceOf(address(token), alice), 300 ether);
        assertEq(pool.totalLiabilities(address(token)), 300 ether);
        assertEq(token.balanceOf(address(pool)), 300 ether);
    }

    function _sign(bytes32 digest_) internal returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ALICE_PK, digest_);
        return abi.encodePacked(r, s, v);
    }
}
