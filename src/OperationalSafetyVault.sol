// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20Minimal} from "./interfaces/IERC20Minimal.sol";
import {SafeTransferLib} from "./lib/SafeTransferLib.sol";

/// @title OperationalSafetyVault
/// @notice Single-asset custody state machine for graceful degradation and incident response.
contract OperationalSafetyVault {
    using SafeTransferLib for address;

    enum Mode {
        Active,
        ExitOnly,
        Halted
    }

    error Unauthorized();
    error ZeroAddress();
    error ZeroAmount();
    error InvalidConfiguration();
    error ModeNotActive(Mode current);
    error WithdrawalsHalted();
    error InsufficientBalance();
    error UnbackedLiability(uint256 assets, uint256 liabilitiesAfter);
    error SequencerStillFresh(uint256 age, uint256 threshold);
    error SolventState(uint256 assets, uint256 liabilities);
    error RecoveryNotScheduled();
    error RecoveryNotReady(uint256 readyAt, uint256 currentTime);
    error SequencerStale(uint256 age, uint256 threshold);
    error Insolvent(uint256 assets, uint256 liabilities);
    error UnexpectedTransferBehavior(uint256 expected, uint256 vaultSpent, uint256 userReceived);
    error ReentrantCall();

    event Deposited(address indexed user, uint256 requestedAmount, uint256 creditedAmount);
    event Withdrawn(address indexed user, uint256 amount);
    event StateChangeApplied(address indexed user, int256 delta);
    event SequencerHeartbeat(uint256 timestamp);
    event ModeChanged(
        Mode indexed previousMode,
        Mode indexed newMode,
        bytes32 indexed reason,
        address caller
    );
    event RecoveryScheduled(uint256 readyAt);
    event RecoveryExecuted(uint256 timestamp);

    bytes32 public constant REASON_SEQUENCER_INACTIVE = keccak256("SEQUENCER_INACTIVE");
    bytes32 public constant REASON_INSOLVENT = keccak256("INSOLVENT");

    address public immutable token;
    address public immutable owner;
    address public immutable sequencer;
    address public immutable guardian;
    address public immutable monitor;
    uint256 public immutable inactivityThreshold;
    uint256 public immutable recoveryDelay;

    Mode public mode;
    uint256 public lastSequencerUpdate;
    uint256 public recoveryReadyAt;
    uint256 public totalLiabilities;

    mapping(address user => uint256 amount) public balanceOf;

    bool private locked;

    modifier nonReentrant() {
        if (locked) revert ReentrantCall();
        locked = true;
        _;
        locked = false;
    }

    modifier onlyOwner() {
        if (msg.sender != owner) revert Unauthorized();
        _;
    }

    modifier onlySequencer() {
        if (msg.sender != sequencer) revert Unauthorized();
        _;
    }

    modifier onlyGuardian() {
        if (msg.sender != guardian) revert Unauthorized();
        _;
    }

    modifier onlyMonitorOrGuardian() {
        if (msg.sender != monitor && msg.sender != guardian) revert Unauthorized();
        _;
    }

    modifier onlyActive() {
        if (mode != Mode.Active) revert ModeNotActive(mode);
        _;
    }

    constructor(
        address token_,
        address owner_,
        address sequencer_,
        address guardian_,
        address monitor_,
        uint256 inactivityThreshold_,
        uint256 recoveryDelay_
    ) {
        if (
            token_ == address(0) || owner_ == address(0) || sequencer_ == address(0)
                || guardian_ == address(0) || monitor_ == address(0)
        ) revert ZeroAddress();
        if (inactivityThreshold_ == 0 || recoveryDelay_ == 0) revert InvalidConfiguration();

        token = token_;
        owner = owner_;
        sequencer = sequencer_;
        guardian = guardian_;
        monitor = monitor_;
        inactivityThreshold = inactivityThreshold_;
        recoveryDelay = recoveryDelay_;
        lastSequencerUpdate = block.timestamp;
    }

    function deposit(uint256 requestedAmount)
        external
        onlyActive
        nonReentrant
        returns (uint256 creditedAmount)
    {
        if (requestedAmount == 0) revert ZeroAmount();

        uint256 assetsBefore = assets();
        token.safeTransferFrom(msg.sender, address(this), requestedAmount);
        uint256 assetsAfter = assets();

        creditedAmount = assetsAfter - assetsBefore;
        if (creditedAmount == 0) revert ZeroAmount();

        balanceOf[msg.sender] += creditedAmount;
        totalLiabilities += creditedAmount;

        emit Deposited(msg.sender, requestedAmount, creditedAmount);
    }

    /// @notice User exits remain available in Active and ExitOnly modes.
    function withdraw(uint256 amount) external nonReentrant {
        if (mode == Mode.Halted) revert WithdrawalsHalted();
        if (amount == 0) revert ZeroAmount();

        uint256 claim = balanceOf[msg.sender];
        if (claim < amount) revert InsufficientBalance();

        uint256 vaultAssetsBefore = assets();
        uint256 userAssetsBefore = IERC20Minimal(token).balanceOf(msg.sender);

        balanceOf[msg.sender] = claim - amount;
        totalLiabilities -= amount;

        token.safeTransfer(msg.sender, amount);

        uint256 vaultSpent = vaultAssetsBefore - assets();
        uint256 userReceived = IERC20Minimal(token).balanceOf(msg.sender) - userAssetsBefore;

        if (vaultSpent != amount || userReceived != amount) {
            revert UnexpectedTransferBehavior(amount, vaultSpent, userReceived);
        }

        emit Withdrawn(msg.sender, amount);
    }

    /// @notice Sequencer-controlled internal claim update while the system is fully active.
    function applyStateChange(address user, int256 delta) external onlySequencer onlyActive {
        if (user == address(0)) revert ZeroAddress();
        if (delta == 0) {
            _heartbeat();
            return;
        }

        if (delta > 0) {
            uint256 amount = uint256(delta);
            uint256 liabilitiesAfter = totalLiabilities + amount;
            uint256 currentAssets = assets();

            if (liabilitiesAfter > currentAssets) {
                revert UnbackedLiability(currentAssets, liabilitiesAfter);
            }

            balanceOf[user] += amount;
            totalLiabilities = liabilitiesAfter;
        } else {
            uint256 amount = uint256(-delta);
            uint256 claim = balanceOf[user];
            if (claim < amount) revert InsufficientBalance();

            balanceOf[user] = claim - amount;
            totalLiabilities -= amount;
        }

        _heartbeat();
        emit StateChangeApplied(user, delta);
    }

    /// @notice Sequencer can prove liveness even while degraded; this never auto-resumes the vault.
    function heartbeat() external onlySequencer {
        _heartbeat();
    }

    /// @notice Authorized monitoring can immediately stop new risk while preserving user exits.
    function enterExitOnly(bytes32 reason) external onlyMonitorOrGuardian {
        if (mode != Mode.Active) revert ModeNotActive(mode);
        _setMode(Mode.ExitOnly, reason);
    }

    /// @notice Anyone can activate exit-only mode once sequencer liveness exceeds the threshold.
    function enterExitOnlyIfSequencerInactive() external {
        if (mode != Mode.Active) revert ModeNotActive(mode);

        uint256 age = block.timestamp - lastSequencerUpdate;
        if (age < inactivityThreshold) revert SequencerStillFresh(age, inactivityThreshold);

        _setMode(Mode.ExitOnly, REASON_SEQUENCER_INACTIVE);
    }

    /// @notice Guardian can fully halt transfers for severe exploit containment.
    function halt(bytes32 reason) external onlyGuardian {
        if (mode == Mode.Halted) revert WithdrawalsHalted();
        _setMode(Mode.Halted, reason);
    }

    /// @notice Anyone can halt once actual token backing falls below internal liabilities.
    function haltIfInsolvent() external {
        uint256 currentAssets = assets();
        if (currentAssets >= totalLiabilities) {
            revert SolventState(currentAssets, totalLiabilities);
        }

        if (mode != Mode.Halted) {
            _setMode(Mode.Halted, REASON_INSOLVENT);
        }
    }

    /// @notice Recovery is intentionally delayed and never automatic.
    function scheduleRecovery() external onlyOwner {
        if (mode == Mode.Active) revert ModeNotActive(mode);

        recoveryReadyAt = block.timestamp + recoveryDelay;
        emit RecoveryScheduled(recoveryReadyAt);
    }

    /// @notice Recovery requires elapsed delay, restored solvency, and a fresh sequencer heartbeat.
    function executeRecovery() external onlyOwner {
        if (mode == Mode.Active) revert ModeNotActive(mode);

        uint256 readyAt = recoveryReadyAt;
        if (readyAt == 0) revert RecoveryNotScheduled();
        if (block.timestamp < readyAt) revert RecoveryNotReady(readyAt, block.timestamp);

        uint256 currentAssets = assets();
        if (currentAssets < totalLiabilities) {
            revert Insolvent(currentAssets, totalLiabilities);
        }

        uint256 age = block.timestamp - lastSequencerUpdate;
        if (age >= inactivityThreshold) revert SequencerStale(age, inactivityThreshold);

        Mode previous = mode;
        mode = Mode.Active;
        recoveryReadyAt = 0;

        emit ModeChanged(previous, Mode.Active, bytes32(0), msg.sender);
        emit RecoveryExecuted(block.timestamp);
    }

    function assets() public view returns (uint256) {
        return IERC20Minimal(token).balanceOf(address(this));
    }

    function isSolvent() external view returns (bool) {
        return assets() >= totalLiabilities;
    }

    function _heartbeat() internal {
        lastSequencerUpdate = block.timestamp;
        emit SequencerHeartbeat(block.timestamp);
    }

    function _setMode(Mode newMode, bytes32 reason) internal {
        Mode previous = mode;
        mode = newMode;
        recoveryReadyAt = 0;

        emit ModeChanged(previous, newMode, reason, msg.sender);
    }
}
