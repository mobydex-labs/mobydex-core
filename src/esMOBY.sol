// SPDX-License-Identifier: MIT

pragma solidity 0.8.16;

import {ERC20} from "@openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin-contracts/contracts/access/Ownable.sol";

contract esMOBY is ERC20, Ownable {
    using SafeERC20 for IERC20;

    IERC20 public immutable MOBY;

    uint256 public vestingPeriod = 50 days;

    uint256 public withdrawalEnabledTime;

    uint256 public instantWithdrawalEnabledTime;

    uint256 public instantWithdrawalFeeRate = 5000; // 50%

    address public instantWithdrawalFeeReceiver;

    mapping(address => uint256) public lastClaimedTime;

    mapping(address => uint256) public claimablePerSecond;

    mapping(address => uint256) public timeToFullClaim;

    constructor(IERC20 _moby) ERC20("Escrow Mobydex Token", "esMOBY") {
        MOBY = _moby;
    }

    function setVestingPeriod(uint256 _vestingPeriod) public onlyOwner {
        vestingPeriod = _vestingPeriod;
    }

    function setWithdrawalEnabledTime(
        uint256 _withdrawalEnabledTime
    ) public onlyOwner {
        withdrawalEnabledTime = _withdrawalEnabledTime;
    }

    function setWithdrawalFeeRate(
        uint256 _instantWithdrawalFeeRate
    ) public onlyOwner {
        instantWithdrawalFeeRate = _instantWithdrawalFeeRate;
    }

    function setWithdrawalFeeReceiver(
        address _instantWithdrawalFeeReceiver
    ) public onlyOwner {
        instantWithdrawalFeeReceiver = _instantWithdrawalFeeReceiver;
    }

    function setInstantWithdrawalEnabledTime(
        uint256 _instantWithdrawalEnabledTime
    ) public onlyOwner {
        instantWithdrawalEnabledTime = _instantWithdrawalEnabledTime;
    }

    function stake(uint256 amount, address to) public {
        MOBY.safeTransferFrom(address(msg.sender), address(this), amount);

        _mint(to, amount);
    }

    function unstake(uint256 amount) public {
        require(
            block.timestamp > withdrawalEnabledTime,
            "esMOBY: withdrawal is not enabled yet"
        );
        _burn(msg.sender, amount);

        claim();

        uint256 totalAmountToVest = amount;
        if (timeToFullClaim[msg.sender] > block.timestamp) {
            totalAmountToVest +=
                claimablePerSecond[msg.sender] *
                (timeToFullClaim[msg.sender] - block.timestamp);
        }

        claimablePerSecond[msg.sender] = totalAmountToVest / vestingPeriod;
        timeToFullClaim[msg.sender] = block.timestamp + vestingPeriod;
    }

    function instantUnstake(uint256 amount) public {
        require(
            block.timestamp > withdrawalEnabledTime,
            "esMOBY: withdrawal is not enabled yet"
        );
        require(
            block.timestamp > instantWithdrawalEnabledTime,
            "esMOBY: instant withdrawal is not enabled yet"
        );

        _burn(msg.sender, amount);

        uint256 amountToBurn = (amount * instantWithdrawalFeeRate) / 10000;
        MOBY.safeTransfer(instantWithdrawalFeeReceiver, amountToBurn);
        MOBY.safeTransfer(msg.sender, amount - amountToBurn);
    }

    function claim() public {
        uint256 amountToClaim = getClaimable(msg.sender);

        if (amountToClaim > 0) {
            MOBY.safeTransfer(address(msg.sender), amountToClaim);
        }

        lastClaimedTime[msg.sender] = block.timestamp;
    }

    function getClaimable(address user) public view returns (uint256 amount) {
        if (timeToFullClaim[user] > lastClaimedTime[user]) {
            return
                block.timestamp > timeToFullClaim[user]
                    ? claimablePerSecond[user] *
                        (timeToFullClaim[user] - lastClaimedTime[user])
                    : claimablePerSecond[user] *
                        (block.timestamp - lastClaimedTime[user]);
        }
    }

    function getVestingAmount(
        address user
    ) public view returns (uint256 amount) {
        if (timeToFullClaim[user] > block.timestamp) {
            return
                claimablePerSecond[user] *
                (timeToFullClaim[user] - block.timestamp);
        }
    }
}
