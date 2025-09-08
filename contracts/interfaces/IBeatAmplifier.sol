// SPDX-License-Identifier: MIT LICENSE

pragma solidity ^0.8.0;

interface IBeatAmplifier {
    struct sBeatAmplifier {
        uint8 gender; //: male, 1: female 
        uint8 level;
        uint8 cid;
        uint32 tokenId;
        uint16[3] attributes; 
    }

    function updateTokenTraits(sBeatAmplifier memory _s) external;
    function getTokenTraits(uint256 _tokenId) external view returns (sBeatAmplifier memory);
}