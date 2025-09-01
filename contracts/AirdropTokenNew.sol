// SPDX-License-Identifier: MIT
pragma solidity 0.8.0;

import "./library/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import '@openzeppelin/contracts-upgradeable/utils/cryptography/ECDSAUpgradeable.sol';

contract AirdropTokenNew is OwnableUpgradeable, PausableUpgradeable {

    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    address public claimToken;
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
        uint256 dailyClaimAmount;
        address claimer;
    }

    mapping(address => ClaimInfo) public mapUserToClaim;
    uint256 public minBalance;

    event Claim(address indexed account, uint256 totalRewards, uint256 curRewards, uint32 nextClaimTime);

    function initialize() external initializer {
        __Ownable_init();
        authControllers[_msgSender()] = true;
        minBalance = 2e16;
    }

    function setMinBalance(uint256 _bal) external onlyOwner {
        minBalance = _bal;
    }

    function setAuthControllers(address _controller, bool _enable) external onlyOwner {
        authControllers[_controller] = _enable;
    }

    function setParams(
        address _claimToken, 
        uint32 _firstClaimTime, 
        uint32 _gapTime,
        address _signer
    ) onlyOwner external {
        claimToken = _claimToken;
        firstClaimTime = _firstClaimTime;
        gapTime = _gapTime;
        authSigner = _signer; 
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
        uint256 minBalance_) {

        firstClaimTime_ = firstClaimTime;
        gapTime_ = gapTime;
        minBalance_ = minBalance;

        ClaimInfo memory info = mapUserToClaim[_user];
        claimedAmount_ = info.claimedAmount;
        nextClaimTime_ = info.nextClaimTime;
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
        require(_detail.claimer == _msgSender(), "Invalid claimer");
        ClaimInfo memory info = mapUserToClaim[_detail.claimer];
        require(_detail.rewards > info.claimedAmount, "Invalid rewards");
        require(_detail.dailyClaimAmount > 0, "Invalid dailyClaimAmount");
        require(curTime >= info.nextClaimTime, "Not start");

        uint256 curRewards = _detail.rewards - info.claimedAmount;
        if (_detail.dailyClaimAmount < curRewards) {
            curRewards = _detail.dailyClaimAmount;
        }
        IERC20(claimToken).safeTransfer(_msgSender(), curRewards);

        info.claimedAmount += curRewards;
        info.nextClaimTime = ((curTime - firstClaimTime) / gapTime + 1) * gapTime + firstClaimTime;
        mapUserToClaim[_detail.claimer] = info;
        emit Claim(_msgSender(), _detail.rewards, curRewards, info.nextClaimTime);
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