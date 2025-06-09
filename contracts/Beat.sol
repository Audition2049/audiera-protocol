// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "./library/SafeMath.sol";
import "./helpers/ERC20.sol";
import "./helpers/Ownable.sol";

contract Beat is ERC20, Ownable {

    using SafeMath for uint256;
    uint256 public constant MAX_SUPPLY = 1000000000 * 10**18;

    constructor() ERC20("Beat Token", "Beat") {
    }

    function mint(address account_, uint256 amount_) external onlyOwner() {
        uint256 totalSupply_ = totalSupply();
        if (amount_ + totalSupply_ > MAX_SUPPLY) {
            amount_ = MAX_SUPPLY - totalSupply_;
        }
        _mint(account_, amount_);
    }
}