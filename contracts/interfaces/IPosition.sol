// SPDX-License-Identifier: MIT
pragma solidity >=0.5.16;

import "./IPositionalMarket.sol";
import "@openzeppelin/contracts-4.4.1/token/ERC20/IERC20.sol";

interface IPosition is IERC20{
    /* ========== VIEWS / VARIABLES ========== */

    function getTotalSupply() external view returns (uint);

}
