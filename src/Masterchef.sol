// SPDX-License-Identifier: MIT

pragma solidity 0.8.16;

import {IERC20} from "@openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {SafeMath} from "@openzeppelin-contracts/contracts/utils/math/SafeMath.sol";
import {Ownable} from "@openzeppelin-contracts/contracts/access/Ownable.sol";

import {IesMOBY} from "./interfaces/IesMOBY.sol";

interface IMOBY is IERC20 {
    function mintForMasterchef(address _to, uint256 _amount) external;
}

contract Masterchef is Ownable {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    // Info of each user.
    struct UserInfo {
        uint256 amount; // How many LP tokens the user has provided.
        uint256 rewardRewardDebt; // Reward debt. See explanation below.
        uint256 esRewardDebt;
        // uint256 additionalRewardDebt; // Reward debt. See explanation below.
        //
        // We do some fancy math here. Basically, any point in time, the amount of rewards
        // entitled to a user but is pending to be distributed is:
        //
        //   pending reward = (user.amount * pool.accRewardPerShare) - user.rewardRewardDebt
        //
        // Whenever a user deposits or withdraws LP tokens to a pool. Here's what happens:
        //   1. The pool's `accRewardPerShare` (and `lastRewardTime`) gets updated.
        //   2. User receives the pending reward sent to his/her address.
        //   3. User's `amount` gets updated.
        //   4. User's `rewardRewardDebt` gets updated.
    }

    // Info of each pool.
    struct PoolInfo {
        IERC20 lpToken; // Address of LP token contract.
        uint256 rewardAllocPoint; // How many allocation points assigned to this pool. rewards to distribute per block.
        uint256 lastRewardTime; // Last block number that rewards distribution occurs.
        uint256 accRewardPerShare; // Accumulated rewards per share, times 1e12. See below.
        uint256 totalDeposit;
        uint256 accEsRewardPerShare; // Accumulated rewards per share, times 1e12. See below.
    }

    // The reward TOKEN!
    IMOBY public reward;
    // reward tokens created per block.
    uint256 public rewardPerSec;
    uint256 public esRewardPerSec;

    // The block number when reward received its' last reward
    uint256 public lastTeamRewardBlockTime = type(uint256).max;

    // Bonus muliplier for early reward makers.
    uint256 public BONUS_MULTIPLIER = 1;

    // Info of each pool.
    PoolInfo[] public poolInfo;
    // Info of each user that stakes LP tokens.
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;
    // Total allocation poitns. Must be the sum of all allocation points in all pools.
    uint256 public rewardTotalAllocPoint = 0;
    // The block number when reward mining starts.
    uint256 public startTime = type(uint256).max;

    // The amount that the team gets per second (a little over 0.3 a second)
    uint256 public teamRewardPercent = 1000;
    uint256 public constant DENOMINATOR = 10000;

    address public treasury;

    IesMOBY public esMOBY;

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(
        address indexed user,
        uint256 indexed pid,
        uint256 amount
    );

    constructor(
        IMOBY _reward,
        uint256 _rewardPerSec,
        uint256 _esRewardPerSec,
        IesMOBY _esMOBY
    ) {
        reward = _reward; //MOBY
        rewardPerSec = _rewardPerSec; // 0.075e18
        esRewardPerSec = _esRewardPerSec; // 0.075e18
        esMOBY = _esMOBY;

        treasury = msg.sender;

        reward.approve(address(esMOBY), type(uint256).max);
    }

    // Allows users to see if rewards have started
    function rewardsStarted() public view returns (bool) {
        return (block.timestamp >= startTime);
    }

    function updateTreausry(address _treasury) public onlyOwner {
        treasury = _treasury;
    }

    function updateRewardPerSec(uint256 _rewardPerSec) public onlyOwner {
        rewardPerSec = _rewardPerSec;
    }

    function updateEsRewardPerSec(uint256 _esRewardPerSec) public onlyOwner {
        esRewardPerSec = _esRewardPerSec;
    }

    function updateAndSetRewardPerSec(
        uint256 _rewardPerSec,
        uint256 _esRewardPerSec
    ) public onlyOwner {
        massUpdatePools();
        rewardPerSec = _rewardPerSec;
        esRewardPerSec = _esRewardPerSec;
    }

    function updateMultiplier(uint256 multiplierNumber) public onlyOwner {
        BONUS_MULTIPLIER = multiplierNumber;
    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    // Add a new lp to the pool. Can only be called by the owner.
    // XXX DO NOT add the same LP token more than once. Rewards will be messed up if you do.
    function add(
        uint256 _rewardAllocPoint,
        IERC20 _lpToken,
        bool _withUpdate
    ) public onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        uint256 lastRewardTime = block.timestamp > startTime
            ? block.timestamp
            : startTime;
        rewardTotalAllocPoint = rewardTotalAllocPoint.add(_rewardAllocPoint);

        poolInfo.push(
            PoolInfo({
                lpToken: _lpToken,
                rewardAllocPoint: _rewardAllocPoint,
                lastRewardTime: lastRewardTime,
                accRewardPerShare: 0,
                accEsRewardPerShare: 0,
                totalDeposit: 0
            })
        );
    }

    // Update the given pool's reward allocation point. Can only be called by the owner.
    function set(
        uint256 _pid,
        uint256 _rewardAllocPoint,
        bool _withUpdate
    ) public onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        rewardTotalAllocPoint = rewardTotalAllocPoint
            .sub(poolInfo[_pid].rewardAllocPoint)
            .add(_rewardAllocPoint);

        poolInfo[_pid].rewardAllocPoint = _rewardAllocPoint;
    }

    // Return reward multiplier over the given _from to _to block.
    function getMultiplier(
        uint256 _from,
        uint256 _to
    ) public view returns (uint256) {
        return _to.sub(_from).mul(BONUS_MULTIPLIER);
    }

    // View function to see pending rewards on frontend.
    function pendingReward(
        uint256 _pid,
        address _user
    ) public view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accRewardPerShare = pool.accRewardPerShare;
        uint256 lpSupply = pool.totalDeposit;
        if (block.timestamp > pool.lastRewardTime && lpSupply != 0) {
            uint256 multiplier = getMultiplier(
                pool.lastRewardTime,
                block.timestamp
            );
            uint256 rewardReward = multiplier
                .mul(rewardPerSec)
                .mul(pool.rewardAllocPoint)
                .div(rewardTotalAllocPoint);
            accRewardPerShare = accRewardPerShare.add(
                rewardReward.mul(1e12).div(lpSupply)
            );
        }
        return
            user.amount.mul(accRewardPerShare).div(1e12).sub(
                user.rewardRewardDebt
            );
    }

    // View function to see pending rewards on frontend.
    function pendingEsReward(
        uint256 _pid,
        address _user
    ) public view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accRewardPerShare = pool.accEsRewardPerShare;
        uint256 lpSupply = pool.totalDeposit;
        if (block.timestamp > pool.lastRewardTime && lpSupply != 0) {
            uint256 multiplier = getMultiplier(
                pool.lastRewardTime,
                block.timestamp
            );
            uint256 esReward = multiplier
                .mul(esRewardPerSec)
                .mul(pool.rewardAllocPoint)
                .div(rewardTotalAllocPoint);
            accRewardPerShare = accRewardPerShare.add(
                esReward.mul(1e12).div(lpSupply)
            );
        }
        return
            user.amount.mul(accRewardPerShare).div(1e12).sub(user.esRewardDebt);
    }

    // Update reward variables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    // Update reward variables of the given pool to be up-to-date.
    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        if (block.timestamp <= pool.lastRewardTime) {
            return;
        }
        uint256 lpSupply = pool.totalDeposit;
        if (lpSupply == 0) {
            pool.lastRewardTime = block.timestamp;
            return;
        }
        uint256 multiplier = getMultiplier(
            pool.lastRewardTime,
            block.timestamp
        );

        uint256 rewardReward = multiplier
            .mul(rewardPerSec)
            .mul(pool.rewardAllocPoint)
            .div(rewardTotalAllocPoint);

        uint256 esReward = multiplier
            .mul(esRewardPerSec)
            .mul(pool.rewardAllocPoint)
            .div(rewardTotalAllocPoint);

        reward.mintForMasterchef(address(this), rewardReward.add(esReward));

        uint256 teamReward = rewardReward
            .add(esReward)
            .mul(teamRewardPercent)
            .div(10000);
        reward.mintForMasterchef(treasury, teamReward);

        pool.accRewardPerShare = pool.accRewardPerShare.add(
            rewardReward.mul(1e12).div(lpSupply)
        );

        pool.accEsRewardPerShare = pool.accEsRewardPerShare.add(
            esReward.mul(1e12).div(lpSupply)
        );

        pool.lastRewardTime = block.timestamp;
    }

    // transfer pending rewards
    function transferPendingRewards(uint256 _pid, address _account) internal {
        uint256 pendingRewardReward = pendingReward(_pid, _account);
        if (pendingRewardReward > 0) {
            safeRewardTransfer(_account, pendingRewardReward);
        }

        uint256 pendingEsReward_ = pendingEsReward(_pid, _account);
        if (pendingEsReward_ > 0) {
            esMOBY.stake(pendingEsReward_, _account);
        }
    }

    // Deposit LP tokens to MasterChef for reward allocation.
    function deposit(uint256 _pid, uint256 _amount) public {
        require(block.timestamp >= startTime, "Rewards have not yet started");
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        updatePool(_pid);
        if (user.amount > 0) {
            transferPendingRewards(_pid, msg.sender);
        }
        if (_amount > 0) {
            pool.lpToken.safeTransferFrom(
                address(msg.sender),
                address(this),
                _amount
            );
            user.amount = user.amount.add(_amount);
            pool.totalDeposit = pool.totalDeposit.add(_amount);
        }
        user.rewardRewardDebt = user.amount.mul(pool.accRewardPerShare).div(
            1e12
        );
        user.esRewardDebt = user.amount.mul(pool.accEsRewardPerShare).div(1e12);

        emit Deposit(msg.sender, _pid, _amount);
    }

    // Withdraw LP tokens from MasterChef.
    function withdraw(uint256 _pid, uint256 _amount) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.amount >= _amount, "withdraw: not good");
        updatePool(_pid);
        transferPendingRewards(_pid, msg.sender);

        if (_amount > 0) {
            user.amount = user.amount.sub(_amount);
            pool.lpToken.safeTransfer(address(msg.sender), _amount);
            pool.totalDeposit = pool.totalDeposit.sub(_amount);
        }
        user.rewardRewardDebt = user.amount.mul(pool.accRewardPerShare).div(
            1e12
        );
        user.esRewardDebt = user.amount.mul(pool.accEsRewardPerShare).div(1e12);

        emit Withdraw(msg.sender, _pid, _amount);
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        pool.lpToken.safeTransfer(address(msg.sender), user.amount);
        emit EmergencyWithdraw(msg.sender, _pid, user.amount);
        user.amount = 0;
        user.rewardRewardDebt = 0;
        user.esRewardDebt = 0;
    }

    function safeRewardTransfer(address _to, uint256 _amount) internal {
        uint256 rewardBal = reward.balanceOf(address(this));

        bool transferSuccess = false;

        if (_amount > rewardBal) {
            transferSuccess = reward.transfer(_to, rewardBal);
        } else {
            transferSuccess = reward.transfer(_to, _amount);
        }

        require(transferSuccess, "safeEarningsTransfer: transfer failed");
    }

    function setStartTime(uint256 _startTime) external onlyOwner {
        require(block.timestamp < startTime && block.timestamp < _startTime);
        startTime = _startTime;

        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            poolInfo[pid].lastRewardTime = startTime;
        }

        lastTeamRewardBlockTime = startTime;
    }
}
