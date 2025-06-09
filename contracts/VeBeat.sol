// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./helpers/Ownable.sol";

import "./VeERC20.sol";

interface IBoostedMasterChef {
    function updateFactor(address, uint256) external;
}

/// @title Vote Escrow Beat Token - veBeat
/// @notice Infinite supply, used to receive extra farming yields and voting power
contract VeBeat is VeERC20("VeBeat Token", "VeBeat"), Ownable {
    /// @notice the BoostedMasterChef contract
    IBoostedMasterChef public boostedMasterChef;
    mapping(address => bool) public authControllers;

    event UpdateBoostedMasterChef(address indexed user, address boostedMasterChef);

    function setAuthControllers(address _contracts, bool _enable) external onlyOwner {
        authControllers[_contracts] = _enable;
    }

    /// @dev Creates `_amount` token to `_to`. Must only be called by the auth controllers (VeBeatStaking)
    /// @param _to The address that will receive the mint
    /// @param _amount The amount to be minted
    function mint(address _to, uint256 _amount) external {
        require(authControllers[_msgSender()], "no auth");
        _mint(_to, _amount);
    }

    /// @dev Destroys `_amount` tokens from `_from`. Callable only by the auth controllers (VeBeatStaking or VeBeatVote)
    /// @param _from The address that will burn tokens
    /// @param _amount The amount to be burned
    function burnFrom(address _from, uint256 _amount) external {
        require(authControllers[_msgSender()], "no auth");
        _burn(_from, _amount);
    }

    /// @dev Sets the address of the master chef contract this updates
    /// @param _boostedMasterChef the address of BoostedMasterChef
    function setBoostedMasterChef(address _boostedMasterChef) external onlyOwner {
        // We allow 0 address here if we want to disable the callback operations
        boostedMasterChef = IBoostedMasterChef(_boostedMasterChef);

        emit UpdateBoostedMasterChef(_msgSender(), _boostedMasterChef);
    }

    function _afterTokenOperation(address _account, uint256 _newBalance) internal override {
        if (address(boostedMasterChef) != address(0)) {
            boostedMasterChef.updateFactor(_account, _newBalance);
        }
    }

    function renounceOwnership() public override onlyOwner view {
        revert("VeBeatToken: Cannot renounce, can only transfer ownership");
    }
}