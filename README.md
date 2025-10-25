# KipuBankV2
**Evolución de un contrato bancario a un sistema multi-token con límites en USD y control de acceso**
---

## 📌 **Contexto y Objetivos del Proyecto**
Este proyecto representa la **evolución de KipuBank original** hacia una versión lista para producción, aplicando patrones de diseño seguros, mejoras de funcionalidad y mejores prácticas de desarrollo.

**Objetivos cumplidos** (según consigna):
1. **Identificar limitaciones** del contrato original (ej: falta de soporte multi-token, límites fijos en ETH).
2. **Aplicar características avanzadas** de Solidity (roles, oráculos, manejo de decimales).
3. **Refactorizar y extender** el contrato con funcionalidades significativas (soporte para ERC-20, conversión a USD).
4. **Seguir mejores prácticas** en estructura, documentación y despliegue.
5. **Comunicar la solución** mediante un repositorio profesional en GitHub.

---

## ✨ **Mejoras Realizadas y Justificación**
*(Abordando explícitamente las áreas sugeridas en la consigna)*

### 1. **Control de Acceso con OpenZeppelin**
   - **Limitación original**: Cualquiera podía llamar a funciones críticas como `actualizarLimiteGlobal`.
   - **Solución implementada**:
     - Uso de `AccessControl` de OpenZeppelin con **3 roles distintos**:
       - `ADMIN_ROLE`: Configuración global (límites, tokens soportados).
       - `ORACLE_MANAGER_ROLE`: Actualización del feed de Chainlink.
       - `EMERGENCY_WITHDRAWER_ROLE`: Retiros de emergencia.
     - **Código clave**:
       ```solidity
       import "@openzeppelin/contracts/access/AccessControl.sol";
       bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
       ```
   - **Por qué importa**:
     - **Separación de preocupaciones**: Cada rol tiene responsabilidades específicas.
     - **Seguridad**: Reduce el riesgo de acceso no autorizado.

---

### 2. **Soporte Multi-Token (ETH + ERC-20)**
   - **Limitación original**: Solo manejaba ETH.
   - **Solución implementada**:
     - **Mappings anidados** para tracking de saldos:
       ```solidity
       mapping(address => mapping(address => uint256)) private s_saldos;
       ```
     - **`address(0)` para ETH**: Convención estándar para diferenciar tokens nativos.
     - **Función `agregarTokenSoportado`**:
       ```solidity
       function agregarTokenSoportado(address token) external onlyRole(ADMIN_ROLE) {
           s_tokensSoportados[token] = true;
           emit TokenAgregado(token);
       }
       ```
   - **Trade-offs**:
     - ✅ **Flexibilidad**: Soporte para cualquier ERC-20 (USDC, DAI, etc.).
     - ❌ **Complejidad**: Requiere manejo de decimales diferentes (ej: USDC tiene 6 decimales vs. 18 de ETH).

---

### 3. **Contabilidad Interna en USD con Chainlink**
   - **Limitación original**: Límites fijos en ETH (vulnerables a volatilidad).
   - **Solución implementada**:
     - **Integración con Chainlink ETH/USD**:
       ```solidity
       address public immutable i_chainlinkETHUSD = 0x694aa1769357215de4fac081bf1f309adc325306; // Sepolia
       ```
     - **Conversión a USD en tiempo real**:
       ```solidity
       function _getETHValueInUSD(uint256 ethAmount) internal view returns (uint256) {
           (, int256 price, , , ) = AggregatorV3Interface(i_chainlinkETHUSD).latestRoundData();
           require(price > 0, "Chainlink: Precio inválido");
           return (ethAmount * uint256(price)) / 1e10; // Ajuste de decimales (8→18)
       }
       ```
     - **Validaciones de seguridad**:
       - `require(block.timestamp - updatedAt < 12 hours)`: Datos frescos.
       - `require(price > 0)`: Evita precios inválidos.
   - **Por qué importa**:
     - **Protección contra volatilidad**: Los límites en USD se ajustan automáticamente al precio de ETH.
     - **Precisión**: Usa un oráculo descentralizado y confiable.

---

### 4. **Manejo de Decimales y Conversión de Valores**
   - **Limitación original**: No manejaba tokens con decimales distintos a 18.
   - **Solución implementada**:
     - **Conversión de USDC (6 decimales) a 18 decimales**:
       ```solidity
       function _getUSDCValueInUSD(uint256 usdcAmount) internal pure returns (uint256) {
           return usdcAmount * 1e12; // 1 USDC = 1 USD (escalado a 18 decimales)
       }
       ```
     - **Variables constantes para decimales**:
       ```solidity
       uint256 private constant USDC_DECIMALS = 6;
       uint256 private constant ETH_DECIMALS = 18;
       ```
   - **Por qué importa**:
     - **Consistencia**: Todos los cálculos internos usan 18 decimales (estándar de ETH).
     - **Extensibilidad**: Fácil de adaptar para otros tokens (ej: WBTC con 8 decimales).

---

### 5. **Eventos y Manejo de Errores**
   - **Limitación original**: Falta de trazabilidad.
   - **Solución implementada**:
     - **Eventos personalizados**:
       ```solidity
       event DepositoRealizado(address indexed usuario, address indexed token, uint256 monto, uint256 saldoUSD);
       event RetiroRealizado(address indexed usuario, address indexed token, uint256 monto, uint256 saldoUSD);
       event LimiteGlobalActualizado(uint256 nuevoLimiteUSD);
       ```
     - **Errores personalizados** (Solidity 0.8+):
       ```solidity
       error TokenNoSoportado(address token);
       error LimiteGlobalExcedido(uint256 saldoActual, uint256 limite);
       ```
   - **Por qué importa**:
     - **Observabilidad**: Facilita la integración con frontends y herramientas de análisis.
     - **Depuración**: Mensajes de error claros para transacciones fallidas.

---

### 6. **Seguridad y Eficiencia**
   - **Patrón Checks-Effects-Interactions**:
     ```solidity
     function retirar(address token, uint256 monto) external nonReentrant {
         // 1. Checks (validaciones)
         require(s_saldos[msg.sender][token] >= monto, "Saldo insuficiente");
         uint256 valorUSD = _getTokenValueInUSD(token, monto);
         require(i_saldoGlobalUSD + valorUSD <= i_bankCapUSD, "Límite global excedido");

         // 2. Effects (cambios de estado)
         s_saldos[msg.sender][token] -= monto;
         i_saldoGlobalUSD += valorUSD;

         // 3. Interactions (llamadas externas)
         if (token == address(0)) {
             payable(msg.sender).transfer(monto);
         } else {
             IERC20(token).safeTransfer(msg.sender, monto);
         }

         emit RetiroRealizado(msg.sender, token, monto, valorUSD);
     }
     ```
   - **Optimizaciones de gas**:
     - Uso de `immutable` para direcciones constantes.
     - `nonReentrant` para evitar ataques de reentrada.
     - `SafeERC20` para transferencias seguras.

---

## 🚀 **Instrucciones de Despliegue e Interacción**
*(Cumpliendo con el requisito de documentación clara para despliegue y uso)*

### **Requisitos Previos**
| Herramienta | Versión/Detalle |
|-------------|----------------|
| Solidity    | ^0.8.20        |
| Node.js     | v16+           |
| Red         | Sepolia Testnet |
| Dependencias| `@openzeppelin/contracts`, `@chainlink/contracts` |

### **Despliegue en Remix IDE**
1. **Configuración**:
   - Abre [Remix IDE](https://remix.ethereum.org).
   - Carga los archivos desde `/src`.
   - Compila con Solidity 0.8.20.

2. **Parámetros del constructor**:
   ```javascript
   [
       "1000000000000000000",  // 1 ETH (límite de retiro por transacción)
       "1000000",             // $1,000,000 USD (límite global del banco)
       "0x694aa1769357215de4fac081bf1f309adc325306" // Feed ETH/USD de Chainlink (Sepolia)
   ]
