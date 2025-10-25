// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title IERC20Metadata
 * @notice Extensión de IERC20 para obtener metadatos como nombre, símbolo y decimales.
 */
interface IERC20Metadata is IERC20 {
    /**
     * @dev Devuelve el nombre del token.
     */
    function name() external view returns (string memory);

    /**
     * @dev Devuelve el símbolo del token.
     */
    function symbol() external view returns (string memory);

    /**
     * @dev Devuelve el número de decimales del token.
     */
    function decimals() external view returns (uint8);
}