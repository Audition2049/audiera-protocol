// SPDX-License-Identifier: MIT

pragma solidity 0.8.0;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "./library/SafeERC20.sol";
import "./library/SafeMath.sol";
import "./VeBeat.sol";

/// @title Vote Escrow Beat Staking
/// @notice Stake Beat to earn veBeat, which you can use to earn higher farm yields and gain
/// voting power. Note that unstaking any amount of Beat will burn all of your existing veBeat.
contract VeBeatStaking is  OwnableUpgradeable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    /// @notice Info for each user
    /// `balance`: Amount of Beat currently staked by user
    /// `rewardDebt`: The reward debt of the user
    /// `lastClaimTimestamp`: The timestamp of user's last claim or withdraw
    /// `speedUpEndTimestamp`: The timestamp when user stops receiving speed up benefits, or
    /// zero if user is not currently receiving speed up benefits
    struct UserInfo {
        uint256 balance;
        uint256 rewardDebt;
        uint256 lastClaimTimestamp;
        uint256 speedUpEndTimestamp;
        /**
         * @notice We do some fancy math here. Basically, any point in time, the amount of veBeat
         * entitled to a user but is pending to be distributed is:
         *
         *   pendingReward = pendingBaseReward + pendingSpeedUpReward
         *
         *   pendingBaseReward = (user.balance * accVeBeatPerShare) - user.rewardDebt
         *
         *   if user.speedUpEndTimestamp != 0:
         *     speedUpCeilingTimestamp = min(block.timestamp, user.speedUpEndTimestamp)
         *     speedUpSecondsElapsed = speedUpCeilingTimestamp - user.lastClaimTimestamp
         *     pendingSpeedUpReward = speedUpSecondsElapsed * user.balance * speedUpVeBeatPerSharePerSec
         *   else:
         *     pendingSpeedUpReward = 0
         */
    }

    IERC20 public beat;
    VeBeat public veBeat;

    /// @notice The maximum limit of veBeat user can have as percentage points of staked Beat
    /// For example, if user has `n` Beat staked, they can own a maximum of `n * maxCapPct / 100` veBeat.
    uint256 public maxCapPct;

    /// @notice The upper limit of `maxCapPct`
    uint256 public upperLimitMaxCapPct;

    /// @notice The accrued veBeat per share, scaled to `ACC_VEBEAT_PER_SHARE_PRECISION`
    uint256 public accVeBeatPerShare;

    /// @notice Precision of `accVeBeatPerShare`
    uint256 public ACC_VEBEAT_PER_SHARE_PRECISION;

    /// @notice The last time that the reward variables were updated
    uint256 public lastRewardTimestamp;

    /// @notice veBeat per sec per Beat staked, scaled to `VEBEAT_PER_SHARE_PER_SEC_PRECISION`
    uint256 public veBeatPerSharePerSec;

    /// @notice Speed up veBeat per sec per Beat staked, scaled to `VEBEAT_PER_SHARE_PER_SEC_PRECISION`
    uint256 public speedUpVeBeatPerSharePerSec;

    /// @notice The upper limit of `veBeatPerSharePerSec` and `speedUpVeBeatPerSharePerSec`
    uint256 public upperLimitVeBeatPerSharePerSec;

    /// @notice Precision of `veBeatPerSharePerSec`
    uint256 public VEBEAT_PER_SHARE_PER_SEC_PRECISION;

    /// @notice Percentage of user's current staked Beat user has to deposit in order to start
    /// receiving speed up benefits, in parts per 100.
    /// @dev Specifically, user has to deposit at least `speedUpThreshold/100 * userStakedBeat` Beat.
    /// The only exception is the user will also receive speed up benefits if they are depositing
    /// with zero balance
    uint256 public speedUpThreshold;

    /// @notice The length of time a user receives speed up benefits
    uint256 public speedUpDuration;

    mapping(address => UserInfo) public userInfos;

    event Claim(address indexed user, uint256 amount);
    event Deposit(address indexed user, uint256 amount);
    event UpdateMaxCapPct(address indexed user, uint256 maxCapPct);
    event UpdateRewardVars(uint256 lastRewardTimestamp, uint256 accVeBeatPerShare);
    event UpdateSpeedUpThreshold(address indexed user, uint256 speedUpThreshold);
    event UpdateVeBeatPerSharePerSec(address indexed user, uint256 veBeatPerSharePerSec);
    event Withdraw(address indexed user, uint256 withdrawAmount, uint256 burnAmount);

    /// @notice Initialize with needed parameters
    /// @param _beat Address of the Beat token contract
    /// @param _veBeat Address of the veBeat token contract
    function initialize(
        IERC20 _beat,
        VeBeat _veBeat
    ) public initializer {
        __Ownable_init();

        require(address(_beat) != address(0), "VeBeatStaking: unexpected zero address for _beat");
        require(address(_veBeat) != address(0), "VeBeatStaking: unexpected zero address for _veBeat");

        upperLimitVeBeatPerSharePerSec = 1e36;
        upperLimitMaxCapPct = 10000000;

        maxCapPct = 10000;
        speedUpThreshold = 5;
        speedUpDuration = 15 days;
        beat = _beat;
        veBeat = _veBeat;
        uint256 temp = 100 ether;
        veBeatPerSharePerSec = temp / 365 days;
        speedUpVeBeatPerSharePerSec = veBeatPerSharePerSec;
        lastRewardTimestamp = block.timestamp;
        ACC_VEBEAT_PER_SHARE_PRECISION = 1e18;
        VEBEAT_PER_SHARE_PER_SEC_PRECISION = 1e18;
    }

    function setBeat(address _beat) external onlyOwner {
        require(_beat != address(0));
        beat = IERC20(_beat);
    }

    /// @notice Set maxCapPct
    /// @param _maxCapPct The new maxCapPct
    function setMaxCapPct(uint256 _maxCapPct) external onlyOwner {
        require(_maxCapPct > maxCapPct, "VeBeatStaking: expected new _maxCapPct to be greater than existing maxCapPct");
        require(
            _maxCapPct != 0 && _maxCapPct <= upperLimitMaxCapPct,
            "VeBeatStaking: expected new _maxCapPct to be non-zero and <= 10000000"
        );
        maxCapPct = _maxCapPct;
        emit UpdateMaxCapPct(_msgSender(), _maxCapPct);
    }

    /// @notice Set veBeatPerSharePerSec
    /// @param _veBeatPerSharePerSec The new veBeatPerSharePerSec
    function setVeBeatPerSharePerSec(uint256 _veBeatPerSharePerSec) external onlyOwner {
        require(
            _veBeatPerSharePerSec <= upperLimitVeBeatPerSharePerSec,
            "VeBeatStaking: expected _veBeatPerSharePerSec to be <= 1e36"
        );
        updateRewardVars();
        veBeatPerSharePerSec = _veBeatPerSharePerSec;
        emit UpdateVeBeatPerSharePerSec(_msgSender(), _veBeatPerSharePerSec);
    }

    /// @notice Set speedUpThreshold
    /// @param _speedUpThreshold The new speedUpThreshold
    function setSpeedUpThreshold(uint256 _speedUpThreshold) external onlyOwner {
        require(
            _speedUpThreshold != 0 && _speedUpThreshold <= 100,
            "VeBeatStaking: expected _speedUpThreshold to be > 0 and <= 100"
        );
        speedUpThreshold = _speedUpThreshold;
        emit UpdateSpeedUpThreshold(_msgSender(), _speedUpThreshold);
    }

    /// @notice Deposits Beat to start staking for veBeat. Note that any pending veBeat
    /// will also be claimed in the process.
    /// @param _amount The amount of Beat to deposit
    function deposit(uint256 _amount) external {
        require(_amount > 0, "VeBeatStaking: expected deposit amount to be greater than zero");

        updateRewardVars();

        UserInfo storage userInfo = userInfos[_msgSender()];

        if (_getUserHasNonZeroBalance(_msgSender())) {
            // Transfer to the user their pending veBeat before updating their UserInfo
            _claim();

            // We need to update user's `lastClaimTimestamp` to now to prevent
            // passive veBeat accrual if user hit their max cap.
            userInfo.lastClaimTimestamp = block.timestamp;

            uint256 userStakedBeat = userInfo.balance;

            // User is eligible for speed up benefits if `_amount` is at least
            // `speedUpThreshold / 100 * userStakedBeat`
            if (_amount.mul(100) >= speedUpThreshold.mul(userStakedBeat)) {
                userInfo.speedUpEndTimestamp = block.timestamp.add(speedUpDuration);
            }
        } else {
            // If user is depositing with zero balance, they will automatically
            // receive speed up benefits
            userInfo.speedUpEndTimestamp = block.timestamp.add(speedUpDuration);
            userInfo.lastClaimTimestamp = block.timestamp;
        }

        userInfo.balance = userInfo.balance.add(_amount);
        userInfo.rewardDebt = accVeBeatPerShare.mul(userInfo.balance).div(ACC_VEBEAT_PER_SHARE_PRECISION);

        beat.safeTransferFrom(_msgSender(), address(this), _amount);

        emit Deposit(_msgSender(), _amount);
    }

    /// @notice Withdraw staked Beat. Note that unstaking any amount of Beat means you will
    /// lose all of your current veBeat.
    /// @param _amount The amount of Beat to unstake
    function withdraw(uint256 _amount) external {
        require(_amount > 0, "VeBeatStaking: expected withdraw amount to be greater than zero");

        UserInfo storage userInfo = userInfos[_msgSender()];

        require(
            userInfo.balance >= _amount,
            "VeBeatStaking: cannot withdraw greater amount of Beat than currently staked"
        );
        updateRewardVars();

        // Note that we don't need to claim as the user's veBeat balance will be reset to 0
        userInfo.balance = userInfo.balance.sub(_amount);
        userInfo.rewardDebt = accVeBeatPerShare.mul(userInfo.balance).div(ACC_VEBEAT_PER_SHARE_PRECISION);
        userInfo.lastClaimTimestamp = block.timestamp;
        userInfo.speedUpEndTimestamp = 0;

        // Burn the user's current veBeat balance
        uint256 userVeBeatBalance = veBeat.balanceOf(_msgSender());
        veBeat.burnFrom(_msgSender(), userVeBeatBalance);

        // Send user their requested amount of staked Beat
        beat.safeTransfer(_msgSender(), _amount);

        emit Withdraw(_msgSender(), _amount, userVeBeatBalance);
    }

    /// @notice Claim any pending veBeat
    function claim() external {
        require(_getUserHasNonZeroBalance(_msgSender()), "VeBeatStaking: cannot claim veBeat when no Beat is staked");
        updateRewardVars();
        _claim();
    }

    /// @notice Get the pending amount of veBeat for a given user
    /// @param _user The user to lookup
    /// @return The number of pending veBeat tokens for `_user`
    function getPendingVeBeat(address _user) public view returns (uint256) {
        if (!_getUserHasNonZeroBalance(_user)) {
            return 0;
        }

        UserInfo memory user = userInfos[_user];

        // Calculate amount of pending base veBeat
        uint256 _accVeBeatPerShare = accVeBeatPerShare;
        uint256 secondsElapsed = block.timestamp.sub(lastRewardTimestamp);
        if (secondsElapsed > 0) {
            _accVeBeatPerShare = _accVeBeatPerShare.add(
                secondsElapsed.mul(veBeatPerSharePerSec).mul(ACC_VEBEAT_PER_SHARE_PRECISION).div(
                    VEBEAT_PER_SHARE_PER_SEC_PRECISION
                )
            );
        }
        uint256 pendingBaseVeBeat = _accVeBeatPerShare.mul(user.balance).div(ACC_VEBEAT_PER_SHARE_PRECISION).sub(
            user.rewardDebt
        );

        // Calculate amount of pending speed up veBeat
        uint256 pendingSpeedUpVeBeat;
        if (user.speedUpEndTimestamp != 0) {
            uint256 speedUpCeilingTimestamp = block.timestamp > user.speedUpEndTimestamp
                ? user.speedUpEndTimestamp
                : block.timestamp;
            uint256 speedUpSecondsElapsed = speedUpCeilingTimestamp.sub(user.lastClaimTimestamp);
            uint256 speedUpAccVeBeatPerShare = speedUpSecondsElapsed.mul(speedUpVeBeatPerSharePerSec);
            pendingSpeedUpVeBeat = speedUpAccVeBeatPerShare.mul(user.balance).div(VEBEAT_PER_SHARE_PER_SEC_PRECISION);
        }

        uint256 pendingVeBeat = pendingBaseVeBeat.add(pendingSpeedUpVeBeat);

        // Get the user's current veBeat balance
        uint256 userVeBeatBalance = veBeat.balanceOf(_user);

        // This is the user's max veBeat cap multiplied by 100
        uint256 scaledUserMaxVeBeatCap = user.balance.mul(maxCapPct);

        if (userVeBeatBalance.mul(100) >= scaledUserMaxVeBeatCap) {
            // User already holds maximum amount of veBeat so there is no pending veBeat
            return 0;
        } else if (userVeBeatBalance.add(pendingVeBeat).mul(100) > scaledUserMaxVeBeatCap) {
            return scaledUserMaxVeBeatCap.sub(userVeBeatBalance.mul(100)).div(100);
        } else {
            return pendingVeBeat;
        }
    }

    /// @notice Update reward variables
    function updateRewardVars() public {
        if (block.timestamp <= lastRewardTimestamp) {
            return;
        }

        if (beat.balanceOf(address(this)) == 0) {
            lastRewardTimestamp = block.timestamp;
            return;
        }

        uint256 secondsElapsed = block.timestamp.sub(lastRewardTimestamp);
        accVeBeatPerShare = accVeBeatPerShare.add(
            secondsElapsed.mul(veBeatPerSharePerSec).mul(ACC_VEBEAT_PER_SHARE_PRECISION).div(
                VEBEAT_PER_SHARE_PER_SEC_PRECISION
            )
        );
        lastRewardTimestamp = block.timestamp;

        emit UpdateRewardVars(lastRewardTimestamp, accVeBeatPerShare);
    }

    function veBeatStakingInfo(address _user) public view returns (
        uint256 totalStakingBeatAmount_,
        uint256 veBeatTotalSupply_,
        uint256 maxCapPct_,
        uint256 speedUpThreshold_,
        uint256 speedUpDuration_,
        uint256 stakingBeatAmount_,
        uint256 pendingVeBeatAmount_,
        uint256 balanceOfBeat_,
        uint256 balanceOfVeBeat_,
        uint256 speedUpEndTimestamp_,
        uint256 veBeatRewardPerDay_ 
    ){
        totalStakingBeatAmount_ = beat.balanceOf(address(this));
        veBeatTotalSupply_ = veBeat.totalSupply();
        maxCapPct_ = maxCapPct;
        speedUpThreshold_ = speedUpThreshold;
        speedUpDuration_ = speedUpDuration;
        if (_user != address(0)) {
            UserInfo memory userInfo = userInfos[_user];
            stakingBeatAmount_ = userInfo.balance;
            pendingVeBeatAmount_ = getPendingVeBeat(_user);
            balanceOfBeat_ = beat.balanceOf(_user);
            balanceOfVeBeat_ = veBeat.balanceOf(_user);
            speedUpEndTimestamp_ = userInfo.speedUpEndTimestamp;
            uint256 veBeatPerSec = veBeatPerSharePerSec + ((speedUpEndTimestamp_ > block.timestamp) ? speedUpVeBeatPerSharePerSec : 0);
            veBeatRewardPerDay_ = veBeatPerSec * 24 * 3600 * stakingBeatAmount_ / 1e18;
        }
    }

    /// @notice Checks to see if a given user currently has staked Beat
    /// @param _user The user address to check
    /// @return Whether `_user` currently has staked Beat
    function _getUserHasNonZeroBalance(address _user) private view returns (bool) {
        return userInfos[_user].balance > 0;
    }

    /// @dev Helper to claim any pending veBeat
    function _claim() private {
        uint256 veBeatToClaim = getPendingVeBeat(_msgSender());

        UserInfo storage userInfo = userInfos[_msgSender()];

        userInfo.rewardDebt = accVeBeatPerShare.mul(userInfo.balance).div(ACC_VEBEAT_PER_SHARE_PRECISION);

        // If user's speed up period has ended, reset `speedUpEndTimestamp` to 0
        if (userInfo.speedUpEndTimestamp != 0 && block.timestamp >= userInfo.speedUpEndTimestamp) {
            userInfo.speedUpEndTimestamp = 0;
        }

        if (veBeatToClaim > 0) {
            userInfo.lastClaimTimestamp = block.timestamp;

            veBeat.mint(_msgSender(), veBeatToClaim);
            emit Claim(_msgSender(), veBeatToClaim);
        }
    }
}