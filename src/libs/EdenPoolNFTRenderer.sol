// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Base64} from "@openzeppelin/contracts/utils/Base64.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

import "@bokkypoobah/BokkyPooBahsDateTimeLibrary/contracts/BokkyPooBahsDateTimeLibrary.sol";

/**
 * @title Eden Vest NFT Renderer with Advanced Animations
 * @dev Generates unique animated SVG-based NFTs for investment positions
 */
library EdenPoolNFTRenderer {
    using Strings for uint256;

    struct RenderParams {
        uint256 tokenId;
        address investor;
        uint256 amount;
        uint256 depositTime;
        uint256 maturityTime;
        uint256 expectedReturn;
        uint256 actualReturn;
        bool isMatured;
        bool isWithdrawn;
        bool fundsCollected;
        uint256 lockDuration;
        uint256 expectedRate;
    }

    // Brand colors
    string constant BRAND_PURPLE = "#9A74EB";
    string constant BRAND_TEAL = "#21A88C";
    string constant BRAND_DARK = "#222122";
    string constant BRAND_LIGHT = "#F4F1FF";

    /**
     * @dev Main rendering function that generates the complete token URI
     * @param params Struct containing all investment parameters
     * @return Complete data URI for the NFT metadata
     */
    function render(RenderParams memory params) internal view returns (string memory) {
        require(params.amount > 0, "Amount must be greater than 0");
        require(params.maturityTime > params.depositTime, "Maturity time must be after deposit time");
        require(params.expectedRate > 0, "Expected rate must be greater than 0");
        require(params.investor != address(0), "Invalid investor address");

        string memory svg = _generateSVG(params);
        string memory description = _generateDescription(params);

        string memory json = string.concat(
            '{"name":"Eden Vest Position',
            params.tokenId.toString(),
            '","description":"',
            description,
            '","image":"data:image/svg+xml;base64,',
            Base64.encode(bytes(svg)),
            '","attributes":[',
            _generateAttributes(params),
            "]}"
        );

        return string.concat("data:application/json;base64,", Base64.encode(bytes(json)));
    }

    /**
     * @dev Generate the animated SVG artwork for the NFT
     * @param params Investment parameters
     * @return SVG string with animations
     */
    function _generateSVG(RenderParams memory params) internal view returns (string memory) {
        return string.concat(
            '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 350 500">',
            "<defs>",
            _generateGradients(),
            _generatePatterns(),
            _generateFilters(),
            "</defs>",
            "<style>",
            _generateStyles(),
            _generateAnimations(),
            "</style>",
            _renderAnimatedBackground(),
            _renderFloatingParticles(),
            _renderMainCard(),
            _renderHeader(),
            _renderInvestmentDetails(params),
            _renderAnimatedProgressBar(params),
            _renderFooter(params),
            _renderStatusIndicator(params),
            // _renderPulsingEffects(params),
            "</svg>"
        );
    }

    /**
     * @dev Generate enhanced gradients using brand colors
     * @return Gradient definitions
     */
    function _generateGradients() internal pure returns (string memory) {
        return string.concat(
            '<linearGradient id="bgGradient" x1="0%" y1="0%" x2="100%" y2="100%">',
            '<stop offset="0%" style="stop-color:',
            BRAND_DARK,
            ';stop-opacity:1"/>',
            '<stop offset="50%" style="stop-color:',
            BRAND_PURPLE,
            ';stop-opacity:0.8"/>',
            '<stop offset="100%" style="stop-color:',
            BRAND_TEAL,
            ';stop-opacity:0.6"/>',
            "</linearGradient>",
            '<radialGradient id="cardGradient" cx="50%" cy="30%" r="70%">',
            '<stop offset="0%" style="stop-color:',
            BRAND_LIGHT,
            ';stop-opacity:0.15"/>',
            '<stop offset="50%" style="stop-color:',
            BRAND_PURPLE,
            ';stop-opacity:0.1"/>',
            '<stop offset="100%" style="stop-color:',
            BRAND_TEAL,
            ';stop-opacity:0.05"/>',
            "</radialGradient>",
            '<linearGradient id="accentGradient" x1="0%" y1="0%" x2="100%" y2="0%">',
            '<stop offset="0%" style="stop-color:',
            BRAND_TEAL,
            ';stop-opacity:1"/>',
            '<stop offset="50%" style="stop-color:',
            BRAND_PURPLE,
            ';stop-opacity:0.9"/>',
            '<stop offset="100%" style="stop-color:',
            BRAND_TEAL,
            ';stop-opacity:1"/>',
            "</linearGradient>",
            '<linearGradient id="textGradient" x1="0%" y1="0%" x2="100%" y2="0%">',
            '<stop offset="0%" style="stop-color:',
            BRAND_LIGHT,
            ';stop-opacity:1"/>',
            '<stop offset="50%" style="stop-color:',
            BRAND_PURPLE,
            ';stop-opacity:0.9"/>',
            '<stop offset="100%" style="stop-color:',
            BRAND_TEAL,
            ';stop-opacity:1"/>',
            "</linearGradient>",
            '<radialGradient id="glowGradient" cx="50%" cy="50%" r="50%">',
            '<stop offset="0%" style="stop-color:',
            BRAND_PURPLE,
            ';stop-opacity:0.8"/>',
            '<stop offset="70%" style="stop-color:',
            BRAND_TEAL,
            ';stop-opacity:0.3"/>',
            '<stop offset="100%" style="stop-color:transparent;stop-opacity:0"/>',
            "</radialGradient>"
        );
    }

    /**
     * @dev Generate animated patterns
     * @return Pattern definitions
     */
    function _generatePatterns() internal pure returns (string memory) {
        return string.concat(
            '<pattern id="animatedDots" x="0" y="0" width="40" height="40" patternUnits="userSpaceOnUse">',
            '<circle cx="20" cy="20" r="2" fill="',
            BRAND_PURPLE,
            '" opacity="0.3">',
            '<animate attributeName="opacity" values="0.1;0.6;0.1" dur="3s" repeatCount="indefinite"/>',
            '<animate attributeName="r" values="1;3;1" dur="3s" repeatCount="indefinite"/>',
            "</circle>",
            "</pattern>",
            '<pattern id="flowingLines" x="0" y="0" width="60" height="60" patternUnits="userSpaceOnUse">',
            '<path d="M0,30 Q30,0 60,30 T120,30" stroke="',
            BRAND_TEAL,
            '" stroke-width="1" fill="none" opacity="0.2">',
            '<animate attributeName="stroke-dasharray" values="0,100;50,50;100,0" dur="4s" repeatCount="indefinite"/>',
            '<animate attributeName="opacity" values="0.1;0.4;0.1" dur="4s" repeatCount="indefinite"/>',
            "</path>",
            "</pattern>"
        );
    }

    /**
     * @dev Generate SVG filters for glow effects
     * @return Filter definitions
     */
    function _generateFilters() internal pure returns (string memory) {
        return string.concat(
            '<filter id="glow" x="-50%" y="-50%" width="200%" height="200%">',
            '<feGaussianBlur stdDeviation="4" result="coloredBlur"/>',
            "<feMerge>",
            '<feMergeNode in="coloredBlur"/>',
            '<feMergeNode in="SourceGraphic"/>',
            "</feMerge>",
            "</filter>",
            '<filter id="innerGlow" x="-50%" y="-50%" width="200%" height="200%">',
            '<feGaussianBlur stdDeviation="2" result="coloredBlur"/>',
            "<feMerge>",
            '<feMergeNode in="coloredBlur"/>',
            '<feMergeNode in="SourceGraphic"/>',
            "</feMerge>",
            "</filter>"
        );
    }

    /**
     * @dev Generate CSS styles for animations
     * @return Style definitions
     */
    function _generateStyles() internal pure returns (string memory) {
        return string.concat(
            ".title { font: bold 24px sans-serif; fill: url(#textGradient); text-anchor: middle; filter: url(#glow); }",
            ".amount { font: bold 36px sans-serif; fill: url(#textGradient); text-anchor: middle; filter: url(#glow); }",
            ".label { font: normal 14px sans-serif; fill: ",
            BRAND_LIGHT,
            "; opacity: 0.8; }",
            ".value { font: bold 16px sans-serif; fill: ",
            BRAND_LIGHT,
            "; }",
            ".small { font: normal 12px sans-serif; fill: ",
            BRAND_LIGHT,
            "; opacity: 0.7; }",
            ".status { font: bold 14px sans-serif; text-anchor: middle; fill: white; }",
            ".progress-bg { fill: rgba(255,255,255,0.1); }",
            ".progress-fill { fill: url(#accentGradient); filter: url(#innerGlow); }",
            ".card { fill: url(#cardGradient); stroke: ",
            BRAND_PURPLE,
            "; stroke-width: 2; filter: url(#glow); }",
            ".particle { fill: ",
            BRAND_PURPLE,
            "; opacity: 0.6; }",
            ".floating { fill: ",
            BRAND_TEAL,
            "; opacity: 0.4; }"
        );
    }

    /**
     * @dev Generate CSS animations
     * @return Animation definitions
     */
    function _generateAnimations() internal pure returns (string memory) {
        return string.concat(
            "@keyframes float { 0%, 100% { transform: translateY(0px); } 50% { transform: translateY(-10px); } }",
            "@keyframes pulse { 0%, 100% { opacity: 0.5; } 50% { opacity: 1; } }",
            "@keyframes rotate { 0% { transform: rotate(0deg); } 100% { transform: rotate(360deg); } }",
            "@keyframes shimmer { 0% { transform: translateX(-100%); } 100% { transform: translateX(100%); } }",
            "@keyframes breathe { 0%, 100% { transform: scale(1); } 50% { transform: scale(1.02); } }",
            ".animated-bg { animation: breathe 4s ease-in-out infinite; }",
            ".floating-element { animation: float 3s ease-in-out infinite; }",
            ".pulsing { animation: pulse 2s ease-in-out infinite; }",
            ".rotating { animation: rotate 20s linear infinite; }"
        );
    }

    /**
     * @dev Render animated background with moving elements
     * @return Background SVG elements
     */
    function _renderAnimatedBackground() internal pure returns (string memory) {
        return string.concat(
            '<rect width="350" height="500" fill="url(#bgGradient)" class="animated-bg"/>',
            '<rect width="350" height="500" fill="url(#flowingLines)"/>',
            '<rect width="350" height="500" fill="url(#animatedDots)"/>',
            // Animated gradient overlay
            '<rect width="350" height="500" fill="url(#glowGradient)" opacity="0.3">',
            '<animate attributeName="opacity" values="0.1;0.5;0.1" dur="6s" repeatCount="indefinite"/>',
            "</rect>"
        );
    }

    /**
     * @dev Render floating particles
     * @return Particle SVG elements
     */
    function _renderFloatingParticles() internal pure returns (string memory) {
        return string.concat(
            // Floating particles
            '<circle cx="50" cy="100" r="3" class="particle floating-element">',
            '<animate attributeName="cy" values="100;80;100" dur="4s" repeatCount="indefinite"/>',
            '<animate attributeName="opacity" values="0.2;0.8;0.2" dur="4s" repeatCount="indefinite"/>',
            "</circle>",
            '<circle cx="300" cy="200" r="2" class="particle floating-element">',
            '<animate attributeName="cy" values="200;180;200" dur="5s" repeatCount="indefinite"/>',
            '<animate attributeName="opacity" values="0.3;0.7;0.3" dur="5s" repeatCount="indefinite"/>',
            "</circle>",
            '<circle cx="80" cy="350" r="2.5" class="floating floating-element">',
            '<animate attributeName="cy" values="350;330;350" dur="3.5s" repeatCount="indefinite"/>',
            '<animate attributeName="opacity" values="0.2;0.6;0.2" dur="3.5s" repeatCount="indefinite"/>',
            "</circle>",
            '<circle cx="270" cy="450" r="1.5" class="floating floating-element">',
            '<animate attributeName="cy" values="450;430;450" dur="4.5s" repeatCount="indefinite"/>',
            '<animate attributeName="opacity" values="0.1;0.5;0.1" dur="4.5s" repeatCount="indefinite"/>',
            "</circle>"
        );
    }

    /**
     * @dev Render main card with animations
     * @return Card SVG elements
     */
    function _renderMainCard() internal pure returns (string memory) {
        return string.concat(
            '<rect x="20" y="20" width="310" height="460" rx="20" ry="20" class="card">',
            '<animate attributeName="stroke-opacity" values="0.3;0.8;0.3" dur="3s" repeatCount="indefinite"/>',
            "</rect>",
            // Animated border highlight
            '<rect x="20" y="20" width="310" height="460" rx="20" ry="20" fill="none" stroke="url(#accentGradient)" stroke-width="1" opacity="0.5">',
            '<animate attributeName="opacity" values="0.2;0.8;0.2" dur="4s" repeatCount="indefinite"/>',
            "</rect>",
            // Header section with gradient
            '<rect x="20" y="20" width="310" height="80" rx="20" ry="20" fill="',
            BRAND_PURPLE,
            '" opacity="0.2">',
            '<animate attributeName="opacity" values="0.1;0.3;0.1" dur="5s" repeatCount="indefinite"/>',
            "</rect>"
        );
    }

    /**
     * @dev Render animated header section
     * @return Header SVG elements
     */
    function _renderHeader() internal pure returns (string memory) {
        return string.concat(
            '<text x="175" y="50" class="title">Eden Vest Pool</text>',
            '<text x="175" y="75" class="small">Investment Position</text>',
            // Animated divider line
            '<line x1="40" y1="110" x2="310" y2="110" stroke="',
            BRAND_TEAL,
            '" stroke-width="2" opacity="0.6">',
            '<animate attributeName="opacity" values="0.3;0.8;0.3" dur="3s" repeatCount="indefinite"/>',
            '<animate attributeName="stroke-dasharray" values="0,350;175,175;350,0" dur="6s" repeatCount="indefinite"/>',
            "</line>"
        );
    }

    /**
     * @dev Render investment details with animations
     * @param params Investment parameters
     * @return Investment details SVG elements
     */
    function _renderInvestmentDetails(RenderParams memory params) internal pure returns (string memory) {
        return string.concat(
            '<text x="175" y="150" class="amount">',
            _formatAmount(params.amount),
            " cNGN</text>",
            '<text x="175" y="175" class="small">Principal Amount</text>',
            // Animated info boxes
            '<rect x="35" y="195" width="120" height="50" rx="8" fill="',
            BRAND_PURPLE,
            '" opacity="0.1" class="floating-element"/>',
            '<text x="50" y="210" class="label">Estimated Return:</text>',
            '<text x="50" y="230" class="value">',
            _formatAmount(params.expectedReturn),
            " cNGN</text>",
            '<rect x="195" y="195" width="120" height="50" rx="8" fill="',
            BRAND_TEAL,
            '" opacity="0.1" class="floating-element"/>',
            '<text x="200" y="210" class="label">APY:</text>',
            '<text x="200" y="230" class="value">',
            _formatRate(params.expectedRate),
            "%</text>",
            '<rect x="35" y="255" width="120" height="50" rx="8" fill="',
            BRAND_PURPLE,
            '" opacity="0.1" class="floating-element"/>',
            '<text x="50" y="270" class="label">Lock Duration:</text>',
            '<text x="50" y="290" class="value">',
            _formatDuration(params.lockDuration),
            "</text>",
            '<rect x="195" y="255" width="120" height="50" rx="8" fill="',
            BRAND_TEAL,
            '" opacity="0.1" class="floating-element"/>',
            '<text x="200" y="270" class="label">Token ID:</text>',
            '<text x="200" y="290" class="value">#',
            params.tokenId.toString(),
            "</text>"
        );
    }

    /**
     * @dev Render animated progress bar
     * @param params Investment parameters
     * @return Progress bar SVG elements
     */
    function _renderAnimatedProgressBar(RenderParams memory params) internal view returns (string memory) {
        uint256 progress = _calculateProgress(params);
        uint256 progressWidth = (progress * 270) / 100;

        return string.concat(
            '<text x="175" y="340" class="label">Time to Maturity</text>',
            // Progress bar background
            '<rect x="40" y="350" width="270" height="8" rx="4" class="progress-bg"/>',
            // Animated progress fill
            '<rect x="40" y="350" width="',
            progressWidth.toString(),
            '" height="8" rx="4" class="progress-fill">',
            '<animate attributeName="opacity" values="0.7;1;0.7" dur="2s" repeatCount="indefinite"/>',
            "</rect>",
            // Progress indicator dot
            '<circle cx="',
            (40 + progressWidth).toString(),
            '" cy="354" r="6" fill="',
            BRAND_LIGHT,
            '" opacity="0.8" class="pulsing"/>',
            '<text x="175" y="375" class="small">',
            progress.toString(),
            "% Complete</text>"
        );
    }

    /**
     * @dev Render footer with animated elements
     * @param params Investment parameters
     * @return Footer SVG elements
     */
    function _renderFooter(RenderParams memory params) internal pure returns (string memory) {
        return string.concat(
            '<line x1="40" y1="400" x2="310" y2="400" stroke="',
            BRAND_TEAL,
            '" stroke-width="1" opacity="0.4">',
            '<animate attributeName="opacity" values="0.2;0.6;0.2" dur="4s" repeatCount="indefinite"/>',
            "</line>",
            '<text x="50" y="425" class="small">Deposited: ',
            _formatTimestamp(params.depositTime),
            "</text>",
            '<text x="50" y="445" class="small">Matures: ',
            _formatTimestamp(params.maturityTime),
            "</text>"
        );
    }

    /**
     * @dev Render animated status indicator
     * @param params Investment parameters
     * @return Status indicator SVG elements
     */
    function _renderStatusIndicator(RenderParams memory params) internal view returns (string memory) {
        (string memory statusText, string memory statusColor) = _getStatusInfo(params);

        return string.concat(
            '<rect x="200" y="410" width="100" height="25" rx="12" fill="',
            statusColor,
            '" class="pulsing"/>',
            '<text x="250" y="427" class="status">',
            statusText,
            "</text>"
        );
    }

    // /**
    //  * @dev Render pulsing effects based on status
    //  * @param params Investment parameters
    //  * @return Pulsing effect SVG elements
    //  */
    // function _renderPulsingEffects(RenderParams memory params) internal view returns (string memory) {
    //     if (params.isWithdrawn) {
    //         return string.concat(
    //             '<circle cx="175" cy="250" r="100" fill="',
    //             BRAND_TEAL,
    //             '" opacity="0.05" class="pulsing"/>',
    //             '<circle cx="175" cy="250" r="150" fill="',
    //             BRAND_TEAL,
    //             '" opacity="0.02" class="pulsing"/>'
    //         );
    //     } else if (block.timestamp >= params.maturityTime) {
    //         return string.concat(
    //             '<circle cx="175" cy="250" r="100" fill="',
    //             BRAND_PURPLE,
    //             '" opacity="0.05" class="pulsing"/>',
    //             '<circle cx="175" cy="250" r="150" fill="',
    //             BRAND_PURPLE,
    //             '" opacity="0.02" class="pulsing"/>'
    //         );
    //     } else {
    //         return string.concat(
    //             '<circle cx="175" cy="250" r="100" fill="',
    //             BRAND_LIGHT,
    //             '" opacity="0.02" class="pulsing"/>',
    //             '<circle cx="175" cy="250" r="150" fill="',
    //             BRAND_LIGHT,
    //             '" opacity="0.01" class="pulsing"/>'
    //         );
    //     }
    // }

    /**
     * @dev Generate description for NFT metadata
     * @param params Investment parameters
     * @return Description string
     */
    function _generateDescription(RenderParams memory params) internal pure returns (string memory) {
        return string.concat(
            "Investment Position #",
            params.tokenId.toString(),
            " - ",
            _formatAmount(params.amount),
            " cNGN locked for ",
            _formatDuration(params.lockDuration),
            " with expected return of ",
            _formatAmount(params.expectedReturn),
            " cNGN"
        );
    }

    /**
     * @dev Generate attributes for NFT metadata
     * @param params Investment parameters
     * @return Attributes JSON string
     */
    function _generateAttributes(RenderParams memory params) internal view returns (string memory) {
        return string.concat(
            '{"trait_type":"Principal Amount","value":"',
            _formatAmount(params.amount),
            ' cNGN"},',
            '{"trait_type":"Expected Return","value":"',
            _formatAmount(params.expectedReturn),
            ' cNGN"},',
            '{"trait_type":"APY","value":"',
            _formatRate(params.expectedRate),
            '%"},',
            '{"trait_type":"Lock Duration","value":"',
            _formatDuration(params.lockDuration),
            '"},',
            '{"trait_type":"Status","value":"',
            _getStatusText(params),
            '"},',
            '{"trait_type":"Funds Collected","value":"',
            params.fundsCollected ? "Yes" : "No",
            '"}'
        );
    }

    /**
     * @dev Calculate progress percentage
     * @param params Investment parameters
     * @return Progress percentage (0-100)
     */
    function _calculateProgress(RenderParams memory params) internal view returns (uint256) {
        if (block.timestamp >= params.maturityTime) return 100;

        uint256 elapsed = block.timestamp - params.depositTime;
        uint256 total = params.maturityTime - params.depositTime;

        if (total == 0) return 0;
        return (elapsed * 100) / total;
    }

    /**
     * @dev Get status information with brand colors
     * @param params Investment parameters
     * @return Status text and color
     */
    function _getStatusInfo(RenderParams memory params) internal view returns (string memory, string memory) {
        if (params.isWithdrawn) {
            return ("WITHDRAWN", BRAND_TEAL);
        } else if (block.timestamp >= params.maturityTime) {
            return ("MATURE", BRAND_PURPLE);
        } else if (params.fundsCollected) {
            return ("INVESTED", BRAND_TEAL);
        } else {
            return ("DEPOSITED", BRAND_PURPLE);
        }
    }

    /**
     * @dev Get status text only
     * @param params Investment parameters
     * @return Status text
     */
    function _getStatusText(RenderParams memory params) internal view returns (string memory) {
        (string memory statusText,) = _getStatusInfo(params);
        return statusText;
    }

    /**
     * @dev Format amount for display
     * @param amount Amount to format
     * @return Formatted amount string
     */
    function _formatAmount(uint256 amount) internal pure returns (string memory) {
        uint256 wholePart = amount / 1e6;
        return wholePart.toString();
    }

    /**
     * @dev Format rate for display
     * @param rate Rate in basis points
     * @return Formatted rate string
     */
    function _formatRate(uint256 rate) internal pure returns (string memory) {
        uint256 percentage = rate / 100;
        uint256 decimal = (rate % 100) / 10;

        if (decimal == 0) {
            return percentage.toString();
        } else {
            return string.concat(percentage.toString(), ".", decimal.toString());
        }
    }

    /**
     * @dev Format duration for display
     * @param duration Duration in seconds
     * @return Formatted duration string
     */
    function _formatDuration(uint256 duration) internal pure returns (string memory) {
        uint256 days_ = duration / 86400;

        if (days_ == 30) {
            return "30 Days";
        } else if (days_ == 90) {
            return "90 Days";
        } else if (days_ == 180) {
            return "180 Days";
        } else if (days_ == 365) {
            return "1 Year";
        } else {
            return string.concat(days_.toString(), " Days");
        }
    }

    /**
     * @dev Format timestamp for display
     * @param timestamp Unix timestamp
     * @return Formatted date string
     */
    function _formatTimestamp(uint256 timestamp) internal pure returns (string memory) {
        uint256 year = BokkyPooBahsDateTimeLibrary.getYear(timestamp);
        uint256 month = BokkyPooBahsDateTimeLibrary.getMonth(timestamp);
        uint256 day = BokkyPooBahsDateTimeLibrary.getDay(timestamp);

        return string.concat(_formatTwoDigits(day), "-", _formatTwoDigits(month), "-", Strings.toString(year));
    }

    /**
     * @dev Format number to two digits
     * @param number Number to format
     * @return Formatted two-digit string
     */
    function _formatTwoDigits(uint256 number) internal pure returns (string memory) {
        if (number < 10) {
            return string.concat("0", Strings.toString(number));
        } else {
            return Strings.toString(number);
        }
    }
}
