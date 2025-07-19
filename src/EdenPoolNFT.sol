// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "./libs/EdenPoolNFTRenderer.sol";

contract EdenPoolNFT {
    function renderNFT(EdenPoolNFTRenderer.RenderParams memory params) external view returns (string memory) {
        return EdenPoolNFTRenderer.render(params);
    }
}
