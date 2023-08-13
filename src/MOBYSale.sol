// SPDX-License-Identifier: MIT

pragma solidity 0.8.16;

import {IERC20} from "@openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

contract MOBYSale {
    using SafeERC20 for IERC20;

    address public operator;

    bool public initialized;

    uint256 public startTime;
    uint256 public endTime;
    uint256 public claimableTime;

    IERC20 public saleToken;
    IERC20 public raisingToken;
    uint256 public raisingCap;
    uint256 public totalRaisedAmount;

    uint256 public saleTokenPrice; // 15e17

    struct User {
        uint256 committedAmount;
        uint256 claimableAmount;
        bool claimed;
    }

    mapping(address => User) public users;

    constructor() {
        operator = msg.sender;
    }

    function initialize(
        uint256 _startTime,
        uint256 _endTime,
        uint256 _claimableTime,
        IERC20 _saleToken,
        IERC20 _raisingToken,
        uint256 _saleTokenPrice,
        uint256 _raisingCap,
        uint256 _totalRaisedAmount
    ) external {
        require(msg.sender == operator, "MOBYSale: not operator");
        require(!initialized, "MOBYSale: already initialized");

        require(_startTime < _endTime, "MOBYSale: invalid start/end time");
        require(
            _endTime < _claimableTime,
            "MOBYSale: invalid end/claimable time"
        );

        initialized = true;

        startTime = _startTime;
        endTime = _endTime;
        claimableTime = _claimableTime;

        saleToken = _saleToken;
        raisingToken = _raisingToken;
        saleTokenPrice = _saleTokenPrice;

        raisingCap = _raisingCap;
        totalRaisedAmount = _totalRaisedAmount;
    }

    function commit(uint256 raisingTokenAmount) external {
        require(initialized, "MOBYSale: not initialized");
        require(block.timestamp >= startTime, "MOBYSale: not started");
        require(block.timestamp < endTime, "MOBYSale: already ended");

        require(
            totalRaisedAmount + raisingTokenAmount <= raisingCap,
            "MOBYSale: raising cap exceeded"
        );

        raisingToken.safeTransferFrom(
            msg.sender,
            address(this),
            raisingTokenAmount
        );

        uint256 saleTokenAmount = (raisingTokenAmount * 1e18) / saleTokenPrice;

        User storage user = users[msg.sender];

        totalRaisedAmount += raisingTokenAmount;

        user.committedAmount += raisingTokenAmount;
        user.claimableAmount += saleTokenAmount;
    }

    function claim() external {
        require(initialized, "MOBYSale: not initialized");
        require(block.timestamp >= claimableTime, "MOBYSale: not claimable");

        User storage user = users[msg.sender];

        require(!user.claimed, "MOBYSale: already claimed");

        user.claimed = true;
        user.claimableAmount = 0;

        saleToken.safeTransfer(msg.sender, user.claimableAmount);
    }

    function withdrawRaisingToken() external {
        require(msg.sender == operator, "MOBYSale: not operator");

        raisingToken.safeTransfer(
            msg.sender,
            raisingToken.balanceOf(address(this))
        );
    }

    function withdrawUnsoldSaleToken() external {
        require(msg.sender == operator, "MOBYSale: not operator");

        uint256 unsoldAmount = saleToken.balanceOf(address(this)) -
            (totalRaisedAmount * 1e18) /
            saleTokenPrice;
        saleToken.safeTransfer(msg.sender, unsoldAmount);
    }
}
