// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "forge-std/Script.sol";
import "forge-std/console.sol";

/**
 * @title Error Signature Decoder
 * @notice Decode the error signature 0x2083cd40 to identify the specific error
 */
contract DecodeError is Script {
    function run() external view {
        console.log("=== DECODING ERROR SIGNATURE 0x2083cd40 ===");

        // Common EdenVest custom errors and their signatures
        console.log("Checking common EdenVest contract errors...");

        // Calculate selectors for common errors
        bytes4 invalidPoolSig = bytes4(keccak256("InvalidPool()"));
        bytes4 invalidAmountSig = bytes4(keccak256("InvalidAmount()"));
        bytes4 poolNotActiveSig = bytes4(keccak256("PoolNotActive()"));
        bytes4 invalidTaxRateSig = bytes4(keccak256("InvalidTaxRate()"));
        bytes4 invalidAddressSig = bytes4(keccak256("InvalidAddress()"));
        bytes4 transferFailedSig = bytes4(keccak256("TransferFailed()"));
        bytes4 insufficientLiquiditySig = bytes4(keccak256("InsufficientLiquidity()"));
        bytes4 swapFailedSig = bytes4(keccak256("SwapFailed()"));
        bytes4 deadlineExpiredSig = bytes4(keccak256("DeadlineExpired()"));
        bytes4 swapInconsistencySig = bytes4(keccak256("SwapInconsistency()"));
        bytes4 invalidLockDurationSig = bytes4(keccak256("InvalidLockDuration()"));
        bytes4 invalidRateSig = bytes4(keccak256("InvalidRate()"));
        bytes4 invalidPoolNameSig = bytes4(keccak256("InvalidPoolName()"));
        bytes4 insufficientBalanceSig = bytes4(keccak256("InsufficientBalance()"));

        // ERC20 related errors
        bytes4 insufficientAllowanceSig = bytes4(keccak256("ERC20InsufficientAllowance(address,uint256,uint256)"));
        bytes4 insufficientBalanceERC20Sig = bytes4(keccak256("ERC20InsufficientBalance(address,uint256,uint256)"));
        bytes4 invalidApproverSig = bytes4(keccak256("ERC20InvalidApprover(address)"));
        bytes4 invalidSpenderSig = bytes4(keccak256("ERC20InvalidSpender(address)"));

        // Proxy/Upgradeable related errors
        bytes4 unauthorizedSig = bytes4(keccak256("OwnableUnauthorizedAccount(address)"));
        bytes4 invalidOwnerSig = bytes4(keccak256("OwnableInvalidOwner(address)"));

        console.log("Error signature to find: 0x2083cd40");
        console.log("");

        // Check each signature
        console.log("Common EdenVest Errors:");
        _checkSignature("InvalidPool()", invalidPoolSig);
        _checkSignature("InvalidAmount()", invalidAmountSig);
        _checkSignature("PoolNotActive()", poolNotActiveSig);
        _checkSignature("InvalidTaxRate()", invalidTaxRateSig);
        _checkSignature("InvalidAddress()", invalidAddressSig);
        _checkSignature("TransferFailed()", transferFailedSig);
        _checkSignature("InsufficientLiquidity()", insufficientLiquiditySig);
        _checkSignature("SwapFailed()", swapFailedSig);
        _checkSignature("DeadlineExpired()", deadlineExpiredSig);
        _checkSignature("SwapInconsistency()", swapInconsistencySig);
        _checkSignature("InvalidLockDuration()", invalidLockDurationSig);
        _checkSignature("InvalidRate()", invalidRateSig);
        _checkSignature("InvalidPoolName()", invalidPoolNameSig);
        _checkSignature("InsufficientBalance()", insufficientBalanceSig);

        console.log("");
        console.log("ERC20 Errors:");
        _checkSignature("ERC20InsufficientAllowance(address,uint256,uint256)", insufficientAllowanceSig);
        _checkSignature("ERC20InsufficientBalance(address,uint256,uint256)", insufficientBalanceERC20Sig);
        _checkSignature("ERC20InvalidApprover(address)", invalidApproverSig);
        _checkSignature("ERC20InvalidSpender(address)", invalidSpenderSig);

        console.log("");
        console.log("Access Control Errors:");
        _checkSignature("OwnableUnauthorizedAccount(address)", unauthorizedSig);
        _checkSignature("OwnableInvalidOwner(address)", invalidOwnerSig);

        console.log("");
        console.log("If no match found, this might be a custom error from:");
        console.log("1. InvestmentPool contract");
        console.log("2. LPToken contract");
        console.log("3. NFTPositionManager contract");
        console.log("4. TaxCollector contract");
        console.log("5. SwapRouter contract");
    }

    function _checkSignature(string memory errorName, bytes4 signature) internal view {
        if (signature == 0x2083cd40) {
            console.log("MATCH FOUND:", errorName);
            console.log("   Signature:", vm.toString(signature));
        } else {
            console.log("   ", errorName, "->", vm.toString(signature));
        }
    }
}
