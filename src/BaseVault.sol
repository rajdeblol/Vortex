// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {IERC20} from "forge-std/interfaces/IERC20.sol";

/// @title BaseVault - Non-custodial vault on Base Sepolia (real USDC)
contract BaseVault {
    IERC20 public immutable usdc;
    address public immutable oracle; // will point to a read-only view of Ritual oracle

    mapping(address => uint256) public shares;
    uint256 public totalShares;

    event Deposit(address indexed user, uint256 amount, uint256 shares);
    event Withdraw(address indexed user, uint256 amount, uint256 shares);

    constructor(address _usdc, address _oracle) {
        usdc = IERC20(_usdc);
        oracle = _oracle;
    }

    function deposit(uint256 amount) external {
        require(amount > 0, "Zero amount");
        usdc.transferFrom(msg.sender, address(this), amount);

        uint256 s = totalShares == 0 ? amount : (amount * totalShares) / usdc.balanceOf(address(this));
        shares[msg.sender] += s;
        totalShares += s;

        emit Deposit(msg.sender, amount, s);
    }

    function withdraw(uint256 shareAmount) external {
        require(shareAmount > 0 && shares[msg.sender] >= shareAmount, "Insufficient shares");

        uint256 assetAmount = (shareAmount * usdc.balanceOf(address(this))) / totalShares;
        shares[msg.sender] -= shareAmount;
        totalShares -= shareAmount;

        usdc.transfer(msg.sender, assetAmount);
        emit Withdraw(msg.sender, assetAmount, shareAmount);
    }
}