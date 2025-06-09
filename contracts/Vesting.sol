// SPDX-License-Identifier: MIT
pragma solidity 0.8.0;

import "./library/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import '@openzeppelin/contracts-upgradeable/utils/cryptography/ECDSAUpgradeable.sol';

contract Vesting is OwnableUpgradeable {

    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    struct ClaimRecords {
        uint256 claimTime;
        uint256 nextClaimTime;
        uint256 claimedAmount;
    }

    string public name;
    uint256 public firstClaimTime;
    uint256 public countdown;
    uint256 public numOfClaimPerTime;

    mapping(address => bool) public authControllers;
    ClaimRecords[] public claimRecords;
    address public beat;

    event SetParams(address _sender, uint256 _firstClaimTime, uint256 _countdown, uint256 _numOfClaimPerTime);
    event Claim(address _sender, uint256 _claimTime, uint256 _nextClaimTime, uint256 _claimedAmount);

    function initialize(string memory _name, address _beat) external initializer {
        __Ownable_init();
        authControllers[_msgSender()] = true;
        name = _name;
        beat = _beat;
    }

    function setAuthControllers(address _controller, bool _enable) external onlyOwner {
        authControllers[_controller] = _enable;
    }

    function setName(string memory _name) external onlyOwner {
        name = _name;
    }

    function setParams(uint256 _firstClaimTime, uint256 _countdown, uint256 _numOfClaimPerTime) external onlyOwner {
        require(claimRecords.length == 0);
        firstClaimTime = _firstClaimTime;
        countdown = _countdown;
        numOfClaimPerTime = _numOfClaimPerTime;
        emit SetParams(_msgSender(), _firstClaimTime, _countdown, _numOfClaimPerTime);
    }

    function claim() external {
        require(authControllers[_msgSender()], "No auth");
        uint256 curTime = block.timestamp;
        uint256 claimTime = nextClaimTime();
        require(curTime >= claimTime && claimTime > 0, "Not start");
        IERC20(beat).safeTransfer(_msgSender(), numOfClaimPerTime);

        ClaimRecords memory record;
        record.claimTime = curTime;
        record.nextClaimTime =  claimTime + countdown;
        record.claimedAmount = numOfClaimPerTime;
        claimRecords.push(record);

        emit Claim(_msgSender(), record.claimTime, record.nextClaimTime, record.claimedAmount);
    }

    function nextClaimTime() public view returns(uint256) {
        if (claimRecords.length > 0) {
            ClaimRecords memory lastRecord = claimRecords[claimRecords.length - 1];
            return lastRecord.nextClaimTime;
        }
        return firstClaimTime;
    }

    function claimCount() public view returns(uint256) {
        return claimRecords.length;
    }
}