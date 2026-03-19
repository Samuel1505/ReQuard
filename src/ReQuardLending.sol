// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IERC20} from "forge-std/interfaces/IERC20.sol";

/// @title ReQuardLending
/// @notice Minimal custom lending protocol that allows users to:
///         - Deposit LP positions as collateral
///         - Borrow against collateral
///         - Track health factors for liquidation
contract ReQuardLending {
    /// @notice Represents a borrowing position
    struct Position {
        address borrower;
        bytes32 lpPositionId; // Identifier for the LP position in the hook
        uint256 collateralValue; // Current value of LP collateral (in USD or base token)
        uint256 borrowedAmount; // Amount borrowed (in debt token)
        uint256 liquidationThreshold; // Health factor threshold (e.g., 1.2e18 = 120%)
        bool liquidated;
    }

    /// @notice Emitted when a position is created or updated
    event PositionUpdated(
        bytes32 indexed positionId,
        address indexed borrower,
        bytes32 lpPositionId,
        uint256 collateralValue,
        uint256 borrowedAmount,
        uint256 healthFactor
    );

    /// @notice Emitted when debt is repaid
    event DebtRepaid(bytes32 indexed positionId, uint256 amount);

    /// @notice Emitted when a position is liquidated
    event PositionLiquidated(
        bytes32 indexed positionId, address indexed borrower, uint256 repaidAmount, uint256 liquidationFee
    );

    /// @dev Mapping from position ID to position data
    mapping(bytes32 => Position) public positions;

    /// @dev Mapping from borrower to their position IDs
    mapping(address => bytes32[]) public borrowerPositions;

    /// @dev The collateral token (LP token or underlying)
    IERC20 public immutable collateralToken;

    /// @dev The debt token (what users borrow)
    IERC20 public immutable debtToken;

    /// @dev Liquidation fee in basis points (e.g., 50 = 0.5%)
    uint256 public constant LIQUIDATION_FEE_BPS = 50;

    /// @dev Minimum health factor before liquidation (1.2 = 120%)
    uint256 public constant MIN_HEALTH_FACTOR = 1.2e18;

    /// @dev Address authorized to liquidate positions (the hook)
    address public liquidator;

    modifier onlyLiquidator() {
        require(msg.sender == liquidator, "not liquidator");
        _;
    }

    constructor(address _collateralToken, address _debtToken) {
        collateralToken = IERC20(_collateralToken);
        debtToken = IERC20(_debtToken);
    }

    /// @notice Set the liquidator address (should be the hook)
    function setLiquidator(address _liquidator) external {
        require(liquidator == address(0), "liquidator already set");
        liquidator = _liquidator;
    }

    /// @notice Create or update a borrowing position
    /// @param positionId Unique identifier for the position
    /// @param borrower Address of the borrower
    /// @param lpPositionId Identifier of the LP position in the hook
    /// @param collateralValue Current value of the LP collateral
    /// @param borrowedAmount Amount borrowed
    function upsertPosition(
        bytes32 positionId,
        address borrower,
        bytes32 lpPositionId,
        uint256 collateralValue,
        uint256 borrowedAmount
    ) external {
        require(borrower != address(0), "zero borrower");

        bool isNew = positions[positionId].borrower == address(0);

        positions[positionId] = Position({
            borrower: borrower,
            lpPositionId: lpPositionId,
            collateralValue: collateralValue,
            borrowedAmount: borrowedAmount,
            liquidationThreshold: MIN_HEALTH_FACTOR,
            liquidated: positions[positionId].liquidated
        });

        if (isNew) {
            borrowerPositions[borrower].push(positionId);
        }

        uint256 healthFactor = getHealthFactor(positionId);

        emit PositionUpdated(positionId, borrower, lpPositionId, collateralValue, borrowedAmount, healthFactor);
    }

    /// @notice Update collateral value for a position (called by hook when LP value changes)
    function updateCollateralValue(bytes32 positionId, uint256 newCollateralValue) external {
        Position storage pos = positions[positionId];
        require(pos.borrower != address(0), "position not found");
        require(!pos.liquidated, "position liquidated");

        pos.collateralValue = newCollateralValue;

        uint256 healthFactor = getHealthFactor(positionId);

        emit PositionUpdated(
            positionId, pos.borrower, pos.lpPositionId, newCollateralValue, pos.borrowedAmount, healthFactor
        );
    }

    /// @notice Repay debt for a position
    function repayDebt(bytes32 positionId, uint256 amount) external {
        Position storage pos = positions[positionId];
        require(pos.borrower != address(0), "position not found");
        require(!pos.liquidated, "position liquidated");
        require(msg.sender == pos.borrower, "not borrower");

        require(debtToken.transferFrom(msg.sender, address(this), amount), "transfer failed");

        if (amount >= pos.borrowedAmount) {
            pos.borrowedAmount = 0;
        } else {
            pos.borrowedAmount -= amount;
        }

        uint256 healthFactor = getHealthFactor(positionId);

        emit DebtRepaid(positionId, amount);
        emit PositionUpdated(
            positionId, pos.borrower, pos.lpPositionId, pos.collateralValue, pos.borrowedAmount, healthFactor
        );
    }

    /// @notice Liquidate a position (called by hook via destination contract)
    function liquidatePosition(bytes32 positionId)
        external
        onlyLiquidator
        returns (uint256 repaidAmount, uint256 liquidationFee)
    {
        Position storage pos = positions[positionId];
        require(pos.borrower != address(0), "position not found");
        require(!pos.liquidated, "already liquidated");

        uint256 healthFactor = getHealthFactor(positionId);
        require(healthFactor < MIN_HEALTH_FACTOR, "position healthy");

        repaidAmount = pos.borrowedAmount;
        liquidationFee = (pos.collateralValue * LIQUIDATION_FEE_BPS) / 10000;

        pos.liquidated = true;
        pos.borrowedAmount = 0;
        pos.collateralValue = 0;

        emit PositionLiquidated(positionId, pos.borrower, repaidAmount, liquidationFee);
    }

    /// @notice Calculate health factor for a position
    /// @dev Health factor = (collateralValue * liquidationThreshold) / borrowedAmount
    ///      Returns type(uint256).max if no debt
    function getHealthFactor(bytes32 positionId) public view returns (uint256) {
        Position memory pos = positions[positionId];
        if (pos.borrowedAmount == 0) {
            return type(uint256).max;
        }
        return (pos.collateralValue * pos.liquidationThreshold) / pos.borrowedAmount;
    }

    /// @notice Get position data
    function getPosition(bytes32 positionId) external view returns (Position memory) {
        return positions[positionId];
    }

    /// @notice Get all position IDs for a borrower
    function getBorrowerPositions(address borrower) external view returns (bytes32[] memory) {
        return borrowerPositions[borrower];
    }
}
