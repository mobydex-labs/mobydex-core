// SPDX-License-Identifier: MIT

pragma solidity 0.8.16;

import {ERC20} from "@openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

contract MOBY is ERC20 {

    address public masterchef;
    address public masterchefSetter;

    constructor() ERC20("Mobydex Token", "MOBY") {
        masterchefSetter = msg.sender;
    }

    function setMasterchef(address _masterchef) external {
        require(msg.sender == masterchefSetter, "MOBY: only masterchef setter");
        masterchef = _masterchef;
        masterchefSetter = address(0);
    }

    function mintForMasterchef(address to, uint256 amount) external {
        require(msg.sender == masterchef, "MOBY: only masterchef");
        _mint(to, amount);
    }
}
