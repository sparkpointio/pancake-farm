pragma solidity 0.6.12;

import "@pancakeswap/pancake-swap-lib/contracts/math/SafeMath.sol";
import "@pancakeswap/pancake-swap-lib/contracts/token/BEP20/IBEP20.sol";
import "@pancakeswap/pancake-swap-lib/contracts/token/BEP20/SafeBEP20.sol";
import "@pancakeswap/pancake-swap-lib/contracts/access/Ownable.sol";

contract SparkPool is Ownable {
    using SafeMath for uint256;
    using SafeBEP20 for IBEP20;

    // Info of each user.
    struct UserInfo {
        uint256 amount;     // How many LP tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
        //
        // We do some fancy math here. Basically, any point in time, the amount of Token Rewards
        // entitled to a user but is pending to be distributed is:
        //
        //   pending reward = (user.amount * pool.accRewardPerShare) - user.rewardDebt
        //
        // Whenever a user deposits or withdraws LP tokens to a pool. Here's what happens:
        //   1. The pool's `accRewardPerShare` (and `lastRewardBlock`) gets updated.
        //   2. User receives the pending reward sent to his/her address.
        //   3. User's `amount` gets updated.
        //   4. User's `rewardDebt` gets updated.
    }
    mapping (address => UserInfo) public userInfo;

    // Pool Info
    struct PoolInfo {
        uint256 lastRewardBlock;  // Last block number that Token Rewards distribution occurs.
        uint256 accRewardPerShare;  // Accumulated Token Rewards per share, times 1e12. See below.
    }
    PoolInfo public poolInfo;

    // The STAKING TOKEN!
    IBEP20 public stakingToken;
    // The REWARD TOKEN!
    IBEP20 public rewardToken;

    // The total staking token deposits
    uint256 public totalDeposit;


    uint256 public maxStaking;

    // Tokens rewarded per block.
    uint256 public rewardPerBlock;

    // The block number when stakingToken mining starts.
    uint256 public startBlock;
    // The block number when stakingToken mining ends.
    uint256 public bonusEndBlock;


    event Deposit(address indexed user, uint256 amount);
    event Withdraw(address indexed user, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 amount);

    constructor(
        IBEP20 _stakingToken,
        IBEP20 _rewardToken,
        uint256 _rewardPerBlock,
        uint256 _startBlock,
        uint256 _bonusEndBlock
    ) public {
        stakingToken = _stakingToken;
        rewardToken = _rewardToken;
        rewardPerBlock = _rewardPerBlock;
        startBlock = _startBlock;
        bonusEndBlock = _bonusEndBlock;

        // Staking Pool
        poolInfo.lastRewardBlock = startBlock;
        poolInfo.accRewardPerShare = 0;

        totalDeposit = 0;

        maxStaking = 50000000000000000000;
    }

    modifier rewardDone {
      require(bonusEndBlock <= block.number, 'SparkPool: Pool not yet ended');
      _;
    }

    // View function to see pending Reward on frontend.
    function pendingReward(address _user) external view returns (uint256) {
        UserInfo storage user = userInfo[_user];
        uint256 accRewardPerShare = poolInfo.accRewardPerShare;
        uint256 lpSupply = totalDeposit;
        if (block.number > poolInfo.lastRewardBlock && lpSupply != 0) {
            uint256 multiplier = getMultiplier(poolInfo.lastRewardBlock, block.number);
            uint256 tokenReward = multiplier.mul(rewardPerBlock);
            accRewardPerShare = accRewardPerShare.add(tokenReward.mul(1e12).div(lpSupply));
        }
        return user.amount.mul(accRewardPerShare).div(1e12).sub(user.rewardDebt);
    }

    // Update reward variables of the given pool to be up-to-date
    function updatePool() public {
        if (block.number <= poolInfo.lastRewardBlock) {
            return;
        }
        uint256 lpSupply = totalDeposit;
        if (lpSupply == 0) {
            poolInfo.lastRewardBlock = block.number;
            return;
        }
        uint256 multiplier = getMultiplier(poolInfo.lastRewardBlock, block.number);
        uint256 tokenReward = multiplier.mul(rewardPerBlock);
        poolInfo.accRewardPerShare = poolInfo.accRewardPerShare.add(tokenReward.mul(1e12).div(lpSupply));
        poolInfo.lastRewardBlock = block.number;
    }
    
    // EMERGENCY ONLY: Terminate current ongoing pool
    function stopReward() public onlyOwner {
        bonusEndBlock = block.number;
    }

    // Return reward multiplier over the given _from to _to block.
    function getMultiplier(uint256 _from, uint256 _to) public view returns (uint256) {
        if (_to <= bonusEndBlock) {
            return _to.sub(_from);
        } else if (_from >= bonusEndBlock) {
            return 0;
        } else {
            return bonusEndBlock.sub(_from);
        }
    }

    // Stake stakingTokens to SparkPool
    function enterStaking(uint256 _amount) public {
        UserInfo storage user = userInfo[msg.sender];

        require (_amount.add(user.amount) <= maxStaking, 'SparkPool: Exceed max stake');

        updatePool();
        if (user.amount > 0) {
            uint256 pending = user.amount.mul(poolInfo.accRewardPerShare).div(1e12).sub(user.rewardDebt);
            if(pending > 0) {
                rewardToken.safeTransfer(address(msg.sender), pending);
            }
        }
        if(_amount > 0) {
            stakingToken.safeTransferFrom(address(msg.sender), address(this), _amount);
            user.amount = user.amount.add(_amount);
            totalDeposit = totalDeposit.add(_amount);
        }
        user.rewardDebt = user.amount.mul(poolInfo.accRewardPerShare).div(1e12);

        emit Deposit(msg.sender, _amount);
    }

    // Withdraw stakingTokens from SparkPool.
    function leaveStaking(uint256 _amount) public {
        UserInfo storage user = userInfo[msg.sender];
        require(user.amount >= _amount, 'SparkPool: Amount exceeded user available amount');
        updatePool();
        uint256 pending = user.amount.mul(poolInfo.accRewardPerShare).div(1e12).sub(user.rewardDebt);
        if(pending > 0) {
            rewardToken.safeTransfer(address(msg.sender), pending);
        }
        if(_amount > 0) {
            user.amount = user.amount.sub(_amount);
            totalDeposit = totalDeposit.sub(_amount);
            stakingToken.safeTransfer(address(msg.sender), _amount);
        }
        user.rewardDebt = user.amount.mul(poolInfo.accRewardPerShare).div(1e12);

        emit Withdraw(msg.sender, _amount);
    }

    // EMERGENCY ONLY: Withdraw without caring about rewards.
    function emergencyWithdraw() public {
        UserInfo storage user = userInfo[msg.sender];
        stakingToken.safeTransfer(address(msg.sender), user.amount);
        emit EmergencyWithdraw(msg.sender, user.amount);
        totalDeposit = totalDeposit.sub(user.amount);
        user.amount = 0;
        user.rewardDebt = 0;
    }

    // EMERGENCY ONLY: Withdraw reward.
    function emergencyRewardWithdraw(uint256 _amount) public onlyOwner rewardDone {
        require(_amount < rewardToken.balanceOf(address(this)), 'SparkPool: Not enough token/s');
        rewardToken.safeTransfer(address(msg.sender), _amount);
    }
}
