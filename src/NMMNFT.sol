// src/NMMNFT.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "./lib/NMMNFTRenderer.sol";

contract NMMNFT {
    function renderNFT(NMMNFTRenderer.RenderParams memory params) external view returns (string memory) {
        return NMMNFTRenderer.render(params);
    }
}
