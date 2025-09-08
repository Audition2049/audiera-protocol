// SPDX-License-Identifier: MIT LICENSE

pragma solidity ^0.8.0;
import "./library/Strings.sol";
import "./library/Base64.sol";
import "./interfaces/ITraits.sol";
import "./interfaces/IBeatAmplifier.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

contract BeatAmplifierTratis is OwnableUpgradeable, ITraits {
    using Strings for uint256;
    using Base64 for bytes;

    IBeatAmplifier public nft;
    string ipfsHash;

    function initialize() external initializer {
        __Ownable_init();
        ipfsHash = "bafybeiehnz5gy3z32fyvv3pfmxuru2smwuos77l5klzfyenklnvxm773oi";
    }

    function setNft(address _nft) external onlyOwner {
        require(_nft != address(0));
        nft = IBeatAmplifier(_nft);
    }

    function setIpfsHash(string memory _hash) external onlyOwner {
        ipfsHash = _hash;
    }

    function tokenURI(uint256 _tokenId) public view override returns (string memory) {
        IBeatAmplifier.sBeatAmplifier memory d = nft.getTokenTraits(_tokenId);
        string memory imageUrl = getImageUrl(d.cid, d.gender);

        string memory metadata = string(abi.encodePacked(
            '{"name": "Beat Amplifier #',
            _tokenId.toString(),
            '", "description": "Powers up every performance: higher base scores, better reward chances, and amplified $BEAT staking to turn your rhythm into real gains.", ',
            imageUrl,
            ', "attributes":',
            compileAttributes(d),
            "}"
        ));

        return string(abi.encodePacked(
            "data:application/json;base64,",
            bytes(metadata).base64()
        ));
    }

    function getImageUrl(uint256 _cid, uint256 _gender) internal view returns(string memory) {
        if (_gender == 0) {
            return string(abi.encodePacked('"image": "https://audition.mypinata.cloud/ipfs/',
                ipfsHash,
                '/Ray-',
                _cid.toString(),
                '.png"'
            ));
        } else {
            return string(abi.encodePacked('"image": "https://audition.mypinata.cloud/ipfs/',
                ipfsHash,
                '/Kira-',
                _cid.toString(),
                '.png"'
            ));
        }
    }

    function compileAttributes(IBeatAmplifier.sBeatAmplifier memory _s) internal pure returns (string memory) { 
        string memory traits;
        traits = string(abi.encodePacked(
            attributeForTypeAndValue("Level", uint256(_s.level).toString())
        ));
    
        return string(abi.encodePacked(
            '[',
            traits,
            ']'
        ));
    }

    function attributeForTypeAndValue(string memory _traitType, string memory _value) internal pure returns (string memory) {
        return string(abi.encodePacked(
            '{"trait_type":"',
            _traitType,
            '","value":"',
            _value,
            '"}'
        ));
    }
}