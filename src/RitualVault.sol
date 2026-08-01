// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {IERC20} from "forge-std/interfaces/IERC20.sol";

/// @title RitualVault - Non-custodial yield vault on Ritual
/// @notice Users deposit mUSDC. The oracle's suggested weights are consumed
///         by a separate rebalancer (or future on-chain executor).
contract RitualVault {
    IERC20 public immutable asset;
    address public immutable oracle;

    mapping(address => uint256) public shares;
    uint256 public totalShares;

    event Deposit(address indexed user, uint256 amount, uint256 shares);
    event Withdraw(address indexed user, uint256 amount, uint256 shares);

    constructor(address _asset, address _oracle) {
        asset = IERC20(_asset);
        oracle = _oracle;
    }

    function deposit(uint256 amount) external {
        require(amount > 0, "Zero amount");
        asset.transferFrom(msg.sender, address(this), amount);

        uint256 s = totalShares == 0 ? amount : (amount * totalShares) / asset.balanceOf(address(this));
        shares[msg.sender] += s;
        totalShares += s;

        emit Deposit(msg.sender, amount, s);
    }

    function withdraw(uint256 shareAmount) external {
        require(shareAmount > 0 && shares[msg.sender] >= shareAmount, "Insufficient shares");

        uint256 assetAmount = (shareAmount * asset.balanceOf(address(this))) / totalShares;
        shares[msg.sender] -= shareAmount;
        totalShares -= shareAmount;

        asset.transfer(msg.sender, assetAmount);
        emit Withdraw(msg.sender, assetAmount, shareAmount);
    }

    function totalAssets() external view returns (uint256) {
        return asset.balanceOf(address(this));
    }
}