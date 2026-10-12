// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title Simple Escrow Contract
/// @notice Buyer locks ETH; funds are released to the seller or refunded to the buyer.
/// @dev Three roles: buyer (deployer), seller, arbiter (neutral dispute resolver).
contract Escrow {

    // ---------- STATES ----------
    enum State { AWAITING_PAYMENT, FUNDED, COMPLETE, REFUNDED }

    // ---------- STATE VARIABLES ----------
    address public immutable buyer;    // person who pays (deployer)
    address public immutable seller;   // person who receives the money
    address public immutable arbiter;  // neutral third party
    uint256 public amount;             // ETH locked (in wei)
    State   public state;              // current stage of the deal

    // ---------- EVENTS ----------
    event Deposited(address indexed buyer, uint256 amount);
    event Released(address indexed seller, uint256 amount);
    event Refunded(address indexed buyer, uint256 amount);

    // ---------- ACCESS CONTROL / STATE MODIFIERS ----------
    modifier onlyBuyer() {
        require(msg.sender == buyer, "Only buyer");
        _;
    }

    modifier onlyArbiter() {
        require(msg.sender == arbiter, "Only arbiter");
        _;
    }

    modifier onlySellerOrArbiter() {
        require(msg.sender == seller || msg.sender == arbiter, "Only seller or arbiter");
        _;
    }

    modifier inState(State expected) {
        require(state == expected, "Wrong state");
        _;
    }

    // ---------- CONSTRUCTOR ----------
    /// @param _seller  address that will receive the payment
    /// @param _arbiter address that resolves disputes
    constructor(address _seller, address _arbiter) {
        require(_seller != address(0) && _arbiter != address(0), "Invalid address");
        require(_seller != msg.sender, "Buyer cannot be seller");
        require(_arbiter != msg.sender && _arbiter != _seller, "Arbiter must be neutral");

        buyer   = msg.sender;   // deployer is the buyer
        seller  = _seller;
        arbiter = _arbiter;
        state   = State.AWAITING_PAYMENT;
    }

    // ---------- FUND LOCKING ----------
    /// @notice Buyer sends ETH, which is locked inside the contract
    function deposit() external payable onlyBuyer inState(State.AWAITING_PAYMENT) {
        require(msg.value > 0, "Send some ETH");
        amount = msg.value;
        state  = State.FUNDED;
        emit Deposited(msg.sender, msg.value);
    }

    // ---------- FUND RELEASE ----------
    /// @notice Buyer confirms goods received, so money goes to the seller
    function confirmDelivery() external onlyBuyer inState(State.FUNDED) {
        _releaseToSeller();
    }

    /// @notice Arbiter decides in the seller's favour (dispute resolved)
    function releaseByArbiter() external onlyArbiter inState(State.FUNDED) {
        _releaseToSeller();
    }

    // ---------- REFUND ----------
    /// @notice Seller (voluntarily) or arbiter (dispute) returns money to the buyer
    function refundBuyer() external onlySellerOrArbiter inState(State.FUNDED) {
        state = State.REFUNDED;                      // 1. update state FIRST
        uint256 payout = amount;
        amount = 0;
        (bool ok, ) = payable(buyer).call{value: payout}("");  // 2. then send ETH
        require(ok, "Refund failed");
        emit Refunded(buyer, payout);
    }

    // ---------- INTERNAL ----------
    function _releaseToSeller() private {
        state = State.COMPLETE;                      // update state before sending
        uint256 payout = amount;
        amount = 0;
        (bool ok, ) = payable(seller).call{value: payout}("");
        require(ok, "Transfer failed");
        emit Released(seller, payout);
    }

    // ---------- VIEW ----------
    /// @notice ETH currently locked in this contract
    function getBalance() external view returns (uint256) {
        return address(this).balance;
    }
}