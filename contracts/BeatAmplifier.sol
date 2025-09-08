// SPDX-License-Identifier: MIT
pragma solidity 0.8.0;

import "./interfaces/ITraits.sol";
import "./interfaces/IWETH.sol";
import "./interfaces/IBeatAmplifier.sol";
import "./interfaces/ITraits.sol";
import "./interfaces/IRandom.sol";
import "./library/SafeERC20.sol";
import "./library/SafeMath.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import '@openzeppelin/contracts-upgradeable/utils/cryptography/ECDSAUpgradeable.sol';

contract BeatAmplifier is
    OwnableUpgradeable,
    ERC721EnumerableUpgradeable,
    PausableUpgradeable,
    IBeatAmplifier
    
{

    event Mint(
        address indexed account,
        uint256 indexed tokenId,
        uint8 gender,
        uint8 level,
        uint8 cid,
        uint16 attr1,
        uint16 attr2,
        uint16 attr3
    );

    event UpdateTraits(
        address indexed sender, 
        uint256 indexed tokenId,
        uint8 gender,
        uint8 level,
        uint8 cid,
        uint16 attr1,
        uint16 attr2,
        uint16 attr3
    );

    struct MintSignDetail {
        address minter;
        uint8 gender;
    }

    ITraits public traits;
    IRandom public random;

    uint8 public maleCount;
    uint8 public femaleCount;
    uint32 public minted;
    bool public enableTransfer;
    address public authSigner;
    uint32 public freeMintStartTime;
    uint32 public freeMintdEndTime;
    uint32 public maxFreeMintCountPerAccount;
    mapping(address => uint256) public userMinted;
    mapping(uint256 => sBeatAmplifier) public tokenTraits;
    mapping(address => bool) public authControllers;

    function initialize(
        address _traits,
        address _random
    ) external initializer {
        require(_traits != address(0));
        require(_random != address(0));

        __ERC721_init("Beat Amplifier ", "BAT");
        __ERC721Enumerable_init();
        __Ownable_init();
        __Pausable_init();
        traits = ITraits(_traits);
        random = IRandom(_random);
        maleCount = 39;
        femaleCount = 29;
        maxFreeMintCountPerAccount = 1;
    }

    function setEnableTransfer(bool _enable) external onlyOwner {
        enableTransfer = _enable;
    }

    function setSigner(address _signer) external onlyOwner {
        authSigner = _signer;
    }

    function setFreeMintTime(uint32 _startTime, uint32 _endTime) external onlyOwner {
        freeMintStartTime = _startTime;
        freeMintdEndTime = _endTime;
    }

    function setMaxFreeMintCountPerAccount(uint32 _count) external onlyOwner {
        maxFreeMintCountPerAccount = _count;
    }

    function setAuthControllers(address _controller, bool _enable) external onlyOwner {
        authControllers[_controller] = _enable;
    }

    function setNftTypeCount(uint8 _maleCount, uint8 _femaleCount) external onlyOwner {
        require(_maleCount > 0 && _femaleCount > 0);
        maleCount = _maleCount;
        femaleCount = _femaleCount;
    }

    function pause() external onlyOwner whenNotPaused {
        _pause();
    }

    function unpause() external onlyOwner whenPaused {
        _unpause();
    }

    function freeMint(MintSignDetail calldata _detail, bytes calldata _sigDetail) external payable whenNotPaused {
        require(freeMintStartTime > 0 && freeMintdEndTime > 0, "Not start");
        uint32 curTime = uint32(block.timestamp);
        require(curTime >= freeMintStartTime, "Not start");

        require(isSignatureValid(_sigDetail, keccak256(abi.encode(_detail)), authSigner), 'Signature error');
        require(_detail.minter == _msgSender(), "Invalid minter");
        require(_detail.gender == 0 || _detail.gender == 1, "Invalid gender");
        if (maxFreeMintCountPerAccount > 0) {
            require(userMinted[_msgSender()] < maxFreeMintCountPerAccount, "Exceed max free mint count");
        }

        minted++;

        uint256 r = random.randomseed();
        sBeatAmplifier memory s;
        s.gender = _detail.gender;
        s.level = 1;
        if (s.gender == 0) {
            s.cid = uint8(r % maleCount + 1);
        } else {
            s.cid = uint8(r % femaleCount + 1);
        }
        tokenTraits[minted] = s;
        
        _safeMint(_msgSender(), minted);
        userMinted[_msgSender()] += 1;
        emit Mint(_msgSender(), minted, s.gender, s.level, s.cid, s.attributes[0], s.attributes[1], s.attributes[2]);
    }

    function transferFrom(
        address from,
        address to,
        uint256 tokenId
    ) public virtual override {
        require(enableTransfer == true, "disable transfer");
        _transfer(from, to, tokenId);
    }

     function keccak256Detail(MintSignDetail calldata _detail) external pure returns(bytes32) {
        return keccak256(abi.encode(_detail));
    }

    function toEthSignedMessageHash(MintSignDetail calldata _detail) external pure returns(bytes32) {
        bytes32 h = keccak256(abi.encode(_detail));
        return ECDSAUpgradeable.toEthSignedMessageHash(h);
    }

    function recover(MintSignDetail calldata _detail, bytes calldata _sigDetail) external pure returns(address) {
        bytes32 h = keccak256(abi.encode(_detail));
        return ECDSAUpgradeable.recover(ECDSAUpgradeable.toEthSignedMessageHash(h), _sigDetail);
    }

    function abiEncode(MintSignDetail calldata _detail) external pure returns(bytes memory) {
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

    function getTokenTraits(uint256 _tokenId) external view override returns (sBeatAmplifier memory) {
        return tokenTraits[_tokenId];
    }

    function tokenURI(uint256 _tokenId) public view override returns (string memory) {
        require(_exists(_tokenId));
        return traits.tokenURI(_tokenId);
    }

    function updateTokenTraits(sBeatAmplifier memory _s) external override {
        require(authControllers[_msgSender()], "No auth");
        tokenTraits[_s.tokenId] = _s;
        emit UpdateTraits(_msgSender(), _s.tokenId, _s.gender, _s.level, _s.cid, _s.attributes[0], _s.attributes[1], _s.attributes[2]);
    }

    function getNft(address _user) external view returns(sBeatAmplifier memory _s) {
        if (balanceOf(_user) == 0) {
            return _s;
        }

        uint256 tokenId = tokenOfOwnerByIndex(_user, 0);
        return tokenTraits[tokenId];
    }

    function freeMintInfo() external view returns(
        uint32 freeMintStartTime_,
        uint32 freeMintdEndTime_
    ) {
        freeMintStartTime_ = freeMintStartTime;
        freeMintdEndTime_ = freeMintdEndTime;
    }
}