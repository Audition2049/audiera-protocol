// SPDX-License-Identifier: MIT
pragma solidity 0.8.0;

import "./library/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import '@openzeppelin/contracts-upgradeable/utils/cryptography/ECDSAUpgradeable.sol';

contract AirdropBeat is OwnableUpgradeable, PausableUpgradeable {

    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    address public beatToken;
    uint32 public firstClaimTime;
    uint32 public gapTime;
    address public authSigner;
    mapping(address => bool) public authControllers;

    struct ClaimInfo {
        uint256 claimedAmount;
        uint32 nextClaimTime;
    }

    struct ClaimSignDetail {
        uint256 rewards;
        address claimer;
        uint256 chainId;
    }

    struct ClaimSignDetail2 {
        uint256 rewards;
        address claimer;
        address referral;
        uint256 chainId;
    }

    mapping(address => ClaimInfo) public mapUserToClaim;
    uint256 public minBalance;
    uint32 public rewardBuf;
    uint32 public rewardStartTime;
    uint32 public rewardEndTime;
    uint32 public maxRewardCountPerDay;
    mapping(uint32 => uint32) public mapRewardCountPerDay;
    uint32 public maxDrawCountPerDay;
    uint32 public minDrawAmount;
    uint32 public maxDrawAmount;
    mapping(uint32 => uint32) public mapDrawCountPerDay;
    mapping(address => uint32) public mapUserToDrawAmount;

    event Claim(address indexed account, uint256 totalRewards, uint256 curRewards, uint32 nextClaimTime);
    event Claim2(address indexed account, address indexed referral, uint256 totalRewards, uint256 curRewards, uint32 nextClaimTime, uint32 drawAmount);
    event SetParams(address _beatToken, uint32 _firstClaimTime, uint32 _gapTime, address _signer);
    event SetRewardActivities(uint32 _buf, uint32 _startTime, uint32 _endTime, uint32 _maxCount);
    event SetDrawInfo(uint32 _maxDrawCountPerDay, uint32 _minDrawAmount, uint32 _maxDrawAmount);

    function initialize() external initializer {
        __Ownable_init();
        authControllers[_msgSender()] = true;
        minBalance = 2e16;
        _pause();
    }

    function setMinBalance(uint256 _bal) external onlyOwner {
        minBalance = _bal;
    }

    function setAuthControllers(address _controller, bool _enable) external onlyOwner {
        authControllers[_controller] = _enable;
    }

    function setParams(
        address _beatToken, 
        uint32 _firstClaimTime, 
        uint32 _gapTime,
        address _signer
    ) onlyOwner external {
        beatToken = _beatToken;
        firstClaimTime = _firstClaimTime;
        gapTime = _gapTime;
        authSigner = _signer;
        emit SetParams(_beatToken, _firstClaimTime, _gapTime, _signer); 
    }

    function setRewardActivities(uint32 _buf, uint32 _startTime, uint32 _endTime, uint32 _maxCount) onlyOwner external {
        require(_buf <= 20);
        require(_endTime > _startTime);
        rewardBuf = _buf;
        rewardStartTime = _startTime;
        rewardEndTime = _endTime;
        maxRewardCountPerDay = _maxCount;
        emit SetRewardActivities(_buf, _startTime, _endTime, _maxCount);
    }

    function setDrawInfo(uint32 _maxDrawCountPerDay, uint32 _minDrawAmount, uint32 _maxDrawAmount) onlyOwner() external {
        require(_maxDrawAmount >= _minDrawAmount);
        maxDrawCountPerDay = _maxDrawCountPerDay;
        minDrawAmount = _minDrawAmount;
        maxDrawAmount = _maxDrawAmount;
        emit SetDrawInfo(_maxDrawCountPerDay, _minDrawAmount, _maxDrawAmount);
    }

    function airdrop(address[] memory _uesrs, address _token, uint256 _amount) external {
        require(authControllers[_msgSender()], "no auth");
        for (uint256 i = 0; i < _uesrs.length; ++i) {
            IERC20(_token).safeTransfer(_uesrs[i], _amount);
        }
    }

    function airdropBNB(address[] memory _uesrs, uint256 _amount) external {
        require(authControllers[_msgSender()], "no auth");
        for (uint256 i = 0; i < _uesrs.length; ++i) {
            SafeERC20.safeTransferETH(_uesrs[i], _amount);
        }
    }

    function balanceOf(address _token) public view returns(uint256) {
        return IERC20(_token).balanceOf(address(this));
    }

    function getClaimInfo(address _user) public view returns(
        uint32 firstClaimTime_,
        uint32 gapTime_,
        uint256 claimedAmount_, 
        uint32 nextClaimTime_,
        uint256 minBalance_,
        uint256 drawAmount_
    ) {

        firstClaimTime_ = firstClaimTime;
        gapTime_ = gapTime;
        minBalance_ = minBalance;

        ClaimInfo memory info = mapUserToClaim[_user];
        claimedAmount_ = info.claimedAmount;
        nextClaimTime_ = info.nextClaimTime;
        drawAmount_ = mapUserToDrawAmount[_user];
    }

    function getRewardActivities() public view returns(
        uint32 rewardBuf_,
        uint32 rewardStartTime_,
        uint32 rewardEndTime_,
        uint32 maxRewardCountPerDay_,
        uint32 claimedCount_
    ) {
        rewardBuf_ = rewardBuf;
        rewardStartTime_ = rewardStartTime;
        rewardEndTime_ = rewardEndTime;
        maxRewardCountPerDay_ = maxRewardCountPerDay;
        uint32 pTime = pointTime();
        claimedCount_ = mapRewardCountPerDay[pTime];
    }

    function getDrawInfo() public view returns(
        uint32 maxDrawCountPerDay_, 
        uint32 minDrawAmount_, 
        uint32 maxDrawAmount_,
        uint32 claimedCount_
    ) {
        maxDrawCountPerDay_ = maxDrawCountPerDay;
        minDrawAmount_ = minDrawAmount;
        maxDrawAmount_ = maxDrawAmount;
        uint32 pTime = pointTime();
        claimedCount_ = mapDrawCountPerDay[pTime];
    }

    function pause() external onlyOwner whenNotPaused {
        _pause();
    }

    function unpause() external onlyOwner whenPaused {
        _unpause();
    }

    receive() external payable {}

    function claim(ClaimSignDetail calldata _detail, bytes calldata _sigDetail) external whenNotPaused {
        uint32 curTime = uint32(block.timestamp);
        require(curTime >= firstClaimTime, "Not start");
        require(msg.sender.balance >= minBalance, "Account balance does not meet the requirement");
        require(isSignatureValid(_sigDetail, keccak256(abi.encode(_detail)), authSigner), 'Signature error');
        require(_detail.chainId == block.chainid, "Invalid network");
        require(_detail.claimer == _msgSender(), "Invalid claimer");
        ClaimInfo memory info = mapUserToClaim[_detail.claimer];
        require(_detail.rewards > info.claimedAmount, "Invalid rewards");
        require(curTime >= info.nextClaimTime, "Not start");
        uint256 curRewards = _detail.rewards - info.claimedAmount;
        IERC20(beatToken).safeTransfer(_msgSender(), curRewards);

        info.claimedAmount = _detail.rewards;
        info.nextClaimTime = ((curTime - firstClaimTime) / gapTime + 1) * gapTime + firstClaimTime;
        mapUserToClaim[_detail.claimer] = info;
        emit Claim(_msgSender(), _detail.rewards, curRewards, info.nextClaimTime);
    }

    function claim2(ClaimSignDetail2 calldata _detail, bytes calldata _sigDetail) external whenNotPaused {
        uint32 curTime = uint32(block.timestamp);
        require(curTime >= firstClaimTime, "Not start");
        require(msg.sender.balance >= minBalance, "Account balance does not meet the requirement");
        require(isSignatureValid(_sigDetail, keccak256(abi.encode(_detail)), authSigner), 'Signature error');
        require(_detail.chainId == block.chainid, "Invalid network");
        require(_detail.claimer == _msgSender(), "Invalid claimer");
        ClaimInfo memory info = mapUserToClaim[_detail.claimer];
        require(_detail.rewards > info.claimedAmount, "Invalid rewards");
        require(curTime >= info.nextClaimTime, "Not start");
        uint256 curRewards = _detail.rewards - info.claimedAmount;
        uint256 bufRewards = 0;
        uint32 drawAmount = 0;
        if (rewardBuf > 0 && curTime >= rewardStartTime && curTime <= rewardEndTime) {
            uint32 pTime = pointTime();
            if (mapRewardCountPerDay[pTime]  < maxRewardCountPerDay) {
                bufRewards = curRewards * rewardBuf / 100;
                curRewards += bufRewards;
                mapRewardCountPerDay[pTime] += 1;
            }

            if (mapDrawCountPerDay[pTime] < maxDrawCountPerDay && maxDrawAmount > 0) {
                uint32 gap = maxDrawAmount - minDrawAmount + 1;
                uint random = uint(blockhash(block.number - 1));
                drawAmount = random % gap + minDrawAmount;
                curRewards += drawAmount * 1e18;
                mapDrawCountPerDay[pTime] += 1;
                mapUserToDrawAmount[_detail.claimer] += drawAmount;
            }
        }
        IERC20(beatToken).safeTransfer(_msgSender(), curRewards);
        if (bufRewards > 0 && _detail.referral != address(0)) {
            IERC20(beatToken).safeTransfer(_detail.referral, bufRewards);
        }

        info.claimedAmount = _detail.rewards;
        info.nextClaimTime = ((curTime - firstClaimTime) / gapTime + 1) * gapTime + firstClaimTime;
        mapUserToClaim[_detail.claimer] = info;
        emit Claim2(_msgSender(), _detail.referral, _detail.rewards, curRewards, info.nextClaimTime, drawAmount);
    }

    function pointTime() public view returns(uint32) {
        uint32 curTime = uint32(block.timestamp);
        if (rewardStartTime == 0 || curTime < rewardStartTime) {
            return 0;
        }
        return ((curTime - rewardStartTime) / gapTime) * gapTime + rewardStartTime;
    }

    function keccak256Detail(ClaimSignDetail calldata _detail) external pure returns(bytes32) {
        return keccak256(abi.encode(_detail));
    }

    function toEthSignedMessageHash(ClaimSignDetail calldata _detail) external pure returns(bytes32) {
        bytes32 h = keccak256(abi.encode(_detail));
        return ECDSAUpgradeable.toEthSignedMessageHash(h);
    }

    function recover(ClaimSignDetail calldata _detail, bytes calldata _sigDetail) external pure returns(address) {
        bytes32 h = keccak256(abi.encode(_detail));
        return ECDSAUpgradeable.recover(ECDSAUpgradeable.toEthSignedMessageHash(h), _sigDetail);
    }

    function abiEncode(ClaimSignDetail calldata _detail) external pure returns(bytes memory) {
        return abi.encode(_detail);
    }

    function toEthSignedMessageHash(bytes32 h) external pure returns(bytes32) {
        return ECDSAUpgradeable.toEthSignedMessageHash(h);
    }

    function isSignatureValid(
        bytes memory signature,
        bytes32 hash,
        address signer
    ) public pure returns (bool) {
        return ECDSAUpgradeable.recover(ECDSAUpgradeable.toEthSignedMessageHash(hash), signature) == signer;
    }
}