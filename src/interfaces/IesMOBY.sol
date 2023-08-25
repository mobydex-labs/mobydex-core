// SPDX-License-Identifier: MIT

pragma solidity 0.8.16;

import {IERC20} from "@openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

interface IesMOBY is IERC20 {
    function stake(uint256 amount, address to) external;
}
