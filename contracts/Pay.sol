// SPDX-License-Identifier: MIT
pragma solidity 0.8.0;

import "./library/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

contract Pay is OwnableUpgradeable {

    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    mapping(address => bool) public authControllers;
    IERC20 public beat;
    event BeatPay(address indexed sender, uint256 amount, string orderId);
    event BnbPay(address indexed sender, uint256 amount, string orderId);

    function initialize(IERC20 _beat) external initializer {
        __Ownable_init();
        beat = _beat;
        authControllers[_msgSender()] = true;
    }

    receive() external payable {}

    function setAuthControllers(address _contracts, bool _enable) external onlyOwner {
        authControllers[_contracts] = _enable;
    }

    function beatPay(string memory _orderId, uint256 _amount) external {
        beat.safeTransferFrom(_msgSender(), address(this), _amount);
        emit BeatPay(_msgSender(), _amount, _orderId);
    }

    function bnbPay(string memory _orderId) external payable {
        emit BnbPay(_msgSender(), msg.value, _orderId);
    }

    function withdrawBNB(address _uesr, uint256 _amount) external {
        require(authControllers[_msgSender()], "no auth");
        uint256 tokenBal = address(this).balance;
        if (_amount == 0 || _amount >= tokenBal) {
            _amount = tokenBal;
        }
        SafeERC20.safeTransferETH(_uesr, _amount);
    }

    function withdraw(address _token, address _to, uint256 _amount) external {
        require(authControllers[_msgSender()], "no auth");
        uint256 tokenBal = IERC20(_token).balanceOf(address(this));
        if (_amount == 0 || _amount >= tokenBal) {
            _amount = tokenBal;
        }
        IERC20(_token).safeTransfer(_to, _amount);
    }
}