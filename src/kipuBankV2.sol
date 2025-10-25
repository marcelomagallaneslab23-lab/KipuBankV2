// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/*///////////////////////
        Imports
///////////////////////*/
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

/*///////////////////////
        Interfaces (incluidas directamente para evitar dependencias)
///////////////////////*/
interface IERC20Metadata {
    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function decimals() external view returns (uint8);
}

interface IKipuBankV2 {
    // Events
    event DepositoRealizado(address indexed usuario, address indexed token, uint256 monto, uint256 montoUSD);
    event RetiroRealizado(address indexed usuario, address indexed token, uint256 monto, uint256 montoUSD);
    event TokenAgregado(address indexed token, string symbol);
    event LimiteGlobalActualizado(uint256 nuevoLimiteUSD);
    event ChainlinkFeedActualizado(address nuevoFeed);
    event RolAsignado(bytes32 indexed rol, address indexed cuenta);

    // Functions
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

/*///////////////////////
        Custom Errors (Gas-efficient)
///////////////////////*/
error KipuBank__ParametrosInvalidos();
error KipuBank__DireccionInvalida();
error KipuBank__MontoZero();
error KipuBank__SinRolRequerido();
error KipuBank__TokenNoSoportado();
error KipuBank__SaldoInsuficiente(uint256 solicitado, uint256 disponible);
error KipuBank__RetiroExcedeLimite(uint256 solicitado, uint256 limite);
error KipuBank__DepositoExcedeCap(uint256 nuevoTotal, uint256 limite);
error KipuBank__PrecioOracleNoDisponible();
error KipuBank__PrecioDesactualizado();
error KipuBank__ReentranciaDetectada();
error KipuBank__TransferenciaFallida();
error KipuBank__FondosInsuficientes();

/*///////////////////////
        Libraries
///////////////////////*/
using SafeERC20 for IERC20;

/**
 * @title KipuBankV2
 * @notice Contrato bancario multi-token con límites en USD (Chainlink) y control de acceso basado en roles.
 * @dev Usa OpenZeppelin AccessControl para gestión de roles y SafeERC20 para transferencias seguras.
 * @author marcelomagallanes-dev
 * @custom:security-contacts security@example.com
 * @custom:security-review Auditar antes de usar en producción.
 */
contract KipuBankV2 is AccessControl, IKipuBankV2 {
    /*///////////////////////
            Roles (AccessControl)
    ///////////////////////*/
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant ORACLE_MANAGER_ROLE = keccak256("ORACLE_MANAGER_ROLE");
    bytes32 public constant EMERGENCY_WITHDRAWER_ROLE = keccak256("EMERGENCY_WITHDRAWER_ROLE");

    /*///////////////////////
            State Variables
    ///////////////////////*/
    uint256 public i_retiroMaximoETH;       // Límite de retiro por transacción en ETH (wei)
    uint256 public i_bankCapUSD;           // Límite global de depósitos en USD
    address public i_chainlinkETHUSD;     // Dirección del Chainlink ETH/USD Price Feed
    uint256 public s_totalDepositosUSD;    // Total de depósitos en el banco (en USD)
    uint256 public s_numDepositos;         // Contador de depósitos realizados
    uint256 public s_numRetiros;           // Contador de retiros realizados
    mapping(address => mapping(address => uint256)) public s_bovedas;       // usuario => token => saldo
    mapping(address => bool) public s_tokensSoportados;                       // Tokens ERC-20 soportados
    bool private locked;                   // Flag para protección contra reentrancia

    /*///////////////////////
            Constants
    ///////////////////////*/
    uint256 private constant ORACLE_HEARTBEAT = 12 hours;      // Latido máximo del oracle
    uint256 private constant DECIMAL_FACTOR = 1e10;           // Factor de conversión (ETH:18 decimales, Chainlink:8)

    /*///////////////////////
            Constructor
    ///////////////////////*/
    constructor(
        uint256 _retiroMaximoETH,
        uint256 _bankCapUSD,
        address _chainlinkETHUSD
    ) {
        if (_retiroMaximoETH == 0 || _bankCapUSD == 0 || _chainlinkETHUSD == address(0)) {
            revert KipuBank__ParametrosInvalidos();
        }

        i_retiroMaximoETH = _retiroMaximoETH;
        i_bankCapUSD = _bankCapUSD;
        i_chainlinkETHUSD = _chainlinkETHUSD;

        _grantRole(ADMIN_ROLE, msg.sender);
        _grantRole(ORACLE_MANAGER_ROLE, msg.sender);
        _grantRole(EMERGENCY_WITHDRAWER_ROLE, msg.sender);

        s_tokensSoportados[address(0)] = true;  // ETH como token soportado
        emit TokenAgregado(address(0), "ETH");
    }

    /*///////////////////////
            Modifiers
    ///////////////////////*/
    modifier nonReentrant() {
        if (locked) revert KipuBank__ReentranciaDetectada();
        locked = true;
        _;
        locked = false;
    }

    modifier soloAdmin() {
        if (!hasRole(ADMIN_ROLE, msg.sender)) revert KipuBank__SinRolRequerido();
        _;
    }

    modifier soloOracleManager() {
        if (!hasRole(ORACLE_MANAGER_ROLE, msg.sender)) revert KipuBank__SinRolRequerido();
        _;
    }

    modifier soloEmergencyWithdrawer() {
        if (!hasRole(EMERGENCY_WITHDRAWER_ROLE, msg.sender)) revert KipuBank__SinRolRequerido();
        _;
    }

    /*///////////////////////
            External Functions
    ///////////////////////*/
    function depositar(address token, uint256 monto) external payable nonReentrant override {
        if (monto == 0) revert KipuBank__MontoZero();
        if (!s_tokensSoportados[token]) revert KipuBank__TokenNoSoportado();

        uint256 montoUSD;
        if (token == address(0)) {
            if (msg.value == 0) revert KipuBank__MontoZero();
            if (msg.value != monto) revert("Monto de ETH no coincide con msg.value");
            montoUSD = _getETHValueInUSD(monto);
        } else {
            IERC20(token).safeTransferFrom(msg.sender, address(this), monto);
            montoUSD = _getTokenValueInUSD(token, monto);
        }

        uint256 nuevoTotalUSD = s_totalDepositosUSD + montoUSD;
        if (nuevoTotalUSD > i_bankCapUSD) {
            revert KipuBank__DepositoExcedeCap(nuevoTotalUSD, i_bankCapUSD);
        }

        s_bovedas[msg.sender][token] += monto;
        s_totalDepositosUSD = nuevoTotalUSD;
        s_numDepositos++;

        emit DepositoRealizado(msg.sender, token, monto, montoUSD);
    }

    function retirar(address token, uint256 monto) external nonReentrant override {
        if (monto == 0) revert KipuBank__MontoZero();
        if (!s_tokensSoportados[token]) revert KipuBank__TokenNoSoportado();

        uint256 saldo = s_bovedas[msg.sender][token];
        if (monto > saldo) {
            revert KipuBank__SaldoInsuficiente(monto, saldo);
        }

        if (token == address(0) && monto > i_retiroMaximoETH) {
            revert KipuBank__RetiroExcedeLimite(monto, i_retiroMaximoETH);
        }

        s_bovedas[msg.sender][token] -= monto;
        s_totalDepositosUSD -= _getTokenValueInUSD(token, monto);
        s_numRetiros++;

        if (token == address(0)) {
            _transferirETH(msg.sender, monto);
        } else {
            IERC20(token).safeTransfer(msg.sender, monto);
        }

        emit RetiroRealizado(msg.sender, token, monto, _getTokenValueInUSD(token, monto));
    }

    function agregarTokenSoportado(address token) external soloAdmin override {
        if (s_tokensSoportados[token]) revert("Token ya soportado");
        if (token == address(0)) revert("ETH ya esta soportado");
        s_tokensSoportados[token] = true;
        emit TokenAgregado(token, IERC20Metadata(token).symbol());
    }

    function actualizarLimiteGlobal(uint256 nuevoLimiteUSD) external soloAdmin override {
        emit LimiteGlobalActualizado(nuevoLimiteUSD);
        i_bankCapUSD = nuevoLimiteUSD;
    }

    /**
     * @notice Asigna un rol a una dirección.
     * @dev Solo el admin puede llamar a esta función.
     * @param rol Rol a asignar (ADMIN_ROLE, ORACLE_MANAGER_ROLE).
     * @param cuenta Dirección a la que se asignará el rol.
     */
    function asignarRol(bytes32 rol, address cuenta) external soloAdmin override {
        _grantRole(rol, cuenta);
        emit RolAsignado(rol, cuenta);
    }

    function setChainlinkFeed(address nuevoFeed) external soloOracleManager override {
        if (nuevoFeed == address(0)) revert KipuBank__DireccionInvalida();
        emit ChainlinkFeedActualizado(nuevoFeed);
        i_chainlinkETHUSD = nuevoFeed;
    }

    function retiradaEmergencia(address token, uint256 monto, address destino) external soloEmergencyWithdrawer override {
        if (token == address(0)) {
            if (address(this).balance < monto) revert KipuBank__FondosInsuficientes();
            _transferirETH(destino, monto);
        } else {
            uint256 balanceToken = IERC20(token).balanceOf(address(this));
            if (balanceToken < monto) revert KipuBank__FondosInsuficientes();
            IERC20(token).safeTransfer(destino, monto);
        }
    }

    function consultarSaldo(address usuario, address token) external view override returns (uint256) {
        return s_bovedas[usuario][token];
    }

    function getPrecioETHUSD() external view override returns (int256) {
        (, int256 precio, , , ) = AggregatorV3Interface(i_chainlinkETHUSD).latestRoundData();
        return precio;
    }

    /*///////////////////////
            Internal Functions
    ///////////////////////*/
    function _getETHValueInUSD(uint256 montoETH) internal view returns (uint256) {
        (, int256 precio, , uint256 updatedAt, ) = AggregatorV3Interface(i_chainlinkETHUSD).latestRoundData();
        if (precio <= 0) revert KipuBank__PrecioOracleNoDisponible();
        if (block.timestamp > updatedAt + ORACLE_HEARTBEAT) revert KipuBank__PrecioDesactualizado();
        return (montoETH * uint256(precio)) / DECIMAL_FACTOR;
    }

    function _getTokenValueInUSD(address token, uint256 montoToken) internal view returns (uint256) {
        if (token == address(0)) return _getETHValueInUSD(montoToken);

        // TODO: Implementar oráculos para otros tokens (ej. Chainlink para USDC, DAI)
        // Por ahora, asumimos 1 token = 1 USD (solo válido para stablecoins)
        uint8 decimales = IERC20Metadata(token).decimals();
        if (decimales != 18) {
            montoToken = montoToken * (10 ** (18 - decimales));
        }
        return montoToken;
    }

    function _transferirETH(address destino, uint256 monto) internal {
        (bool exito, ) = destino.call{value: monto}("");
        if (!exito) revert KipuBank__TransferenciaFallida();
    }

}


Direccion de contrato:
https://eth-sepolia.blockscout.com/address/0x1a822D16Ae36795c9f4b85EB72727d2A9A7878a4?tab=contract


