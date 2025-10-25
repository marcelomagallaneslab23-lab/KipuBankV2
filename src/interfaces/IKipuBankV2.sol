// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IKipuBankV2
 * @notice Interfaz del contrato bancario KipuBankV2.
 * @dev Define las funciones públicas y eventos para interoperabilidad.
 */
interface IKipuBankV2 {
    /*///////////////////////
            Eventos
    ///////////////////////*/
    event DepositoRealizado(
        address indexed usuario,
        address indexed token,
        uint256 monto,
        uint256 montoUSD
    );
    event RetiroRealizado(
        address indexed usuario,
        address indexed token,
        uint256 monto,
        uint256 montoUSD
    );
    event TokenAgregado(address indexed token, string simbolo);
    event RolAsignado(bytes32 indexed rol, address indexed cuenta);
    event LimiteGlobalActualizado(uint256 nuevoLimiteUSD);
    event ChainlinkFeedActualizado(address indexed nuevoFeed);

    /*///////////////////////
            Funciones Externas
    ///////////////////////*/
    function depositar(address token, uint256 monto) external payable;

    function retirar(address token, uint256 monto) external;

    function agregarTokenSoportado(address token) external;

    function actualizarLimiteGlobal(uint256 nuevoLimiteUSD) external;

    function asignarRol(bytes32 rol, address cuenta) external;

    function setChainlinkFeed(address nuevoFeed) external;

    function retiradaEmergencia(address token, uint256 monto, address destino) external;

    function consultarSaldo(address usuario, address token) external view returns (uint256);

    function getPrecioETHUSD() external view returns (int256);
}