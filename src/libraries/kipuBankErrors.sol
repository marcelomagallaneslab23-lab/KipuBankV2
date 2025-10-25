// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title KipuBankErrors
 * @notice Biblioteca de errores personalizados para KipuBankV2.
 */
library KipuBankErrors {
    // Depósitos
    string internal constant DEPOSITO_EXCEDE_CAP = "KipuBankV2__DepositoExcedeCap";
    string internal constant MONTO_ZERO = "KipuBankV2__MontoZero";
    string internal constant TOKEN_NO_SOPORTADO = "KipuBankV2__TokenNoSoportado";

    // Retiros
    string internal constant SALDO_INSUFICIENTE = "KipuBankV2__SaldoInsuficiente";
    string internal constant RETIRO_EXCEDE_LIMITE = "KipuBankV2__RetiroExcedeLimite";

    // Oracle/Chainlink
    string internal constant PRECIO_ORACLE_NO_DISPONIBLE = "KipuBankV2__PrecioOracleNoDisponible";
    string internal constant PRECIO_DESACTUALIZADO = "KipuBankV2__PrecioDesactualizado";

    // Seguridad
    string internal constant REENTRANCIA_DETECTADA = "KipuBankV2__ReentranciaDetectada";
    string internal constant TRANSFERENCIA_FALLIDA = "KipuBankV2__TransferenciaFallida";
    string internal constant SIN_ROL_REQUERIDO = "KipuBankV2__SinRolRequerido";

    // Parámetros
    string internal constant PARAMETROS_INVALIDOS = "Parametros invalidos";
    string internal constant DIRECCION_INVALIDA = "Direccion invalida";
}