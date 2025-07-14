// src/NMMNFT.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "./libs/NMMNFTRenderer.sol";

contract NMMNFT {
    function renderNFT(NMMNFTRenderer.RenderParams memory params) external view returns (string memory) {
        return NMMNFTRenderer.render(params);
    }
}
