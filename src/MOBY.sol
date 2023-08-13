// SPDX-License-Identifier: MIT

pragma solidity 0.8.16;

import {ERC20} from "@openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

contract MOBY is ERC20 {
    uint256 public constant MAX_SUPPLY = 20_000_000 ether;

    constructor() ERC20("Mobydex Token", "MOBY") {
        _mint(msg.sender, MAX_SUPPLY);
    }
}
