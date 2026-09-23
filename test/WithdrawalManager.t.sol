// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {ECDSA} from "../src/lib/ECDSA.sol";
import {Pool} from "../src/Pool.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {WithdrawalManager} from "../src/WithdrawalManager.sol";

contract WithdrawalManagerTest is Test {
    uint256 internal constant ALICE_PK = 0xA11CE;
    uint256 internal constant SECP256K1_ORDER =
        0xfffffffffffffffffffffffffffffffebaaedce6af48a03bbfd25e8cd0364141;

    Pool internal pool;
    MockERC20 internal token;
    WithdrawalManager internal manager;

    address internal alice;
    address internal recipient = makeAddr("recipient");
    address internal alternateRecipient = makeAddr("alternate-recipient");
    address internal relayer = makeAddr("relayer");

    function setUp() public {
        alice = vm.addr(ALICE_PK);

        pool = new Pool();
        token = new MockERC20("Standard", "STD");
        manager = new WithdrawalManager(pool);

        pool.setWithdrawalOperator(address(manager), true);

        token.mint(alice, 500 ether);
        vm.startPrank(alice);
        token.approve(address(pool), type(uint256).max);
        pool.deposit(address(token), 500 ether);
        vm.stopPrank();
    }

    function test_relayerCanExecuteValidSignedWithdrawal() public {
        WithdrawalManager.Withdrawal memory request = _request(100 ether, 0);
        bytes memory signature = _sign(manager.digest(request));

        vm.prank(relayer);
        manager.withdrawWithSig(request, signature);

        assertEq(manager.nonces(alice), 1);
        assertEq(token.balanceOf(recipient), 100 ether);
        assertEq(pool.balanceOf(address(token), alice), 400 ether);
        assertEq(pool.totalLiabilities(address(token)), 400 ether);
    }

    function test_replayOfSameSignatureIsRejected() public {
        WithdrawalManager.Withdrawal memory request = _request(100 ether, 0);
        bytes memory signature = _sign(manager.digest(request));

        vm.prank(relayer);
        manager.withdrawWithSig(request, signature);

        vm.prank(relayer);
        vm.expectRevert(abi.encodeWithSelector(WithdrawalManager.InvalidNonce.selector, 1, 0));
        manager.withdrawWithSig(request, signature);

        assertEq(manager.nonces(alice), 1);
        assertEq(token.balanceOf(recipient), 100 ether);
        assertEq(pool.balanceOf(address(token), alice), 400 ether);
    }

    function test_tamperedRecipientInvalidatesSignature() public {
        WithdrawalManager.Withdrawal memory request = _request(100 ether, 0);
        bytes memory signature = _sign(manager.digest(request));

        request.recipient = alternateRecipient;
        address recovered = ECDSA.recover(manager.digest(request), signature);

        vm.prank(relayer);
        vm.expectRevert(
            abi.encodeWithSelector(WithdrawalManager.InvalidSigner.selector, alice, recovered)
        );
        manager.withdrawWithSig(request, signature);

        assertEq(manager.nonces(alice), 0);
        assertEq(token.balanceOf(alternateRecipient), 0);
        assertEq(pool.balanceOf(address(token), alice), 500 ether);
    }

    function test_expiredSignatureIsRejectedWithoutConsumingNonce() public {
        WithdrawalManager.Withdrawal memory request = _request(100 ether, 0);
        request.deadline = block.timestamp - 1;
        bytes memory signature = _sign(manager.digest(request));

        vm.prank(relayer);
        vm.expectRevert(
            abi.encodeWithSelector(WithdrawalManager.Expired.selector, request.deadline)
        );
        manager.withdrawWithSig(request, signature);

        assertEq(manager.nonces(alice), 0);
        assertEq(pool.balanceOf(address(token), alice), 500 ether);
    }

    function test_wrongNonceIsRejected() public {
        WithdrawalManager.Withdrawal memory request = _request(100 ether, 1);
        bytes memory signature = _sign(manager.digest(request));

        vm.prank(relayer);
        vm.expectRevert(abi.encodeWithSelector(WithdrawalManager.InvalidNonce.selector, 0, 1));
        manager.withdrawWithSig(request, signature);

        assertEq(manager.nonces(alice), 0);
    }

    function test_failedPoolWithdrawalRollsNonceBackAtomically() public {
        WithdrawalManager.Withdrawal memory request = _request(600 ether, 0);
        bytes memory signature = _sign(manager.digest(request));

        vm.prank(relayer);
        vm.expectRevert(Pool.InsufficientBalance.selector);
        manager.withdrawWithSig(request, signature);

        assertEq(manager.nonces(alice), 0);
        assertEq(pool.balanceOf(address(token), alice), 500 ether);
        assertEq(token.balanceOf(recipient), 0);
    }

    function test_signatureCannotReplayAcrossManagerContracts() public {
        WithdrawalManager managerB = new WithdrawalManager(pool);
        pool.setWithdrawalOperator(address(managerB), true);

        WithdrawalManager.Withdrawal memory request = _request(100 ether, 0);
        bytes memory signature = _sign(manager.digest(request));

        address recovered = ECDSA.recover(managerB.digest(request), signature);

        vm.prank(relayer);
        vm.expectRevert(
            abi.encodeWithSelector(WithdrawalManager.InvalidSigner.selector, alice, recovered)
        );
        managerB.withdrawWithSig(request, signature);

        assertEq(managerB.nonces(alice), 0);
        assertEq(pool.balanceOf(address(token), alice), 500 ether);
    }

    function test_signatureCannotReplayAcrossChainIds() public {
        WithdrawalManager.Withdrawal memory request = _request(100 ether, 0);
        bytes memory signature = _sign(manager.digest(request));

        vm.chainId(block.chainid + 1);
        address recovered = ECDSA.recover(manager.digest(request), signature);

        vm.prank(relayer);
        vm.expectRevert(
            abi.encodeWithSelector(WithdrawalManager.InvalidSigner.selector, alice, recovered)
        );
        manager.withdrawWithSig(request, signature);

        assertEq(manager.nonces(alice), 0);
        assertEq(pool.balanceOf(address(token), alice), 500 ether);
    }

    function test_highSSignatureMalleabilityIsRejected() public {
        WithdrawalManager.Withdrawal memory request = _request(100 ether, 0);
        bytes32 requestDigest = manager.digest(request);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ALICE_PK, requestDigest);

        bytes32 highS = bytes32(SECP256K1_ORDER - uint256(s));
        uint8 flippedV = v == 27 ? 28 : 27;
        bytes memory malleableSignature = abi.encodePacked(r, highS, flippedV);

        vm.prank(relayer);
        vm.expectRevert(abi.encodeWithSelector(ECDSA.InvalidSignatureS.selector, highS));
        manager.withdrawWithSig(request, malleableSignature);

        assertEq(manager.nonces(alice), 0);
        assertEq(pool.balanceOf(address(token), alice), 500 ether);
    }

    function test_unauthorizedCallerCannotBypassManagerWithWithdrawFor() public {
        vm.prank(relayer);
        vm.expectRevert(Pool.Unauthorized.selector);
        pool.withdrawFor(alice, address(token), recipient, 100 ether);

        assertEq(pool.balanceOf(address(token), alice), 500 ether);
    }

    function _request(uint256 amount, uint256 nonce)
        internal
        view
        returns (WithdrawalManager.Withdrawal memory)
    {
        return WithdrawalManager.Withdrawal({
            user: alice,
            token: address(token),
            recipient: recipient,
            amount: amount,
            nonce: nonce,
            deadline: block.timestamp + 1 days
        });
    }

    function _sign(bytes32 digest_) internal returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ALICE_PK, digest_);
        return abi.encodePacked(r, s, v);
    }
}
