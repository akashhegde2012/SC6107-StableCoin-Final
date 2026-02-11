# Gas Optimization Report

The StableCoin Protocol has been optimized for gas efficiency while maintaining high security and readability standards.

## 1. Custom Errors
Instead of using long string revert messages (e.g., `require(amount > 0, "Amount must be more than zero")`), the protocol uses custom errors (e.g., `revert StableCoinEngine__AmountMustBeMoreThanZero()`).
- **Benefit**: Significant reduction in deployment and execution gas costs, as custom errors only store the 4-byte selector of the error.

## 2. Immutable Variables
Variables that are set once in the constructor and never changed are marked as `immutable`.
- **Examples**: `i_stableCoin` in `StableCoinEngine` and `PSM`.
- **Benefit**: Immutable variables are stored in the contract bytecode rather than storage slots, saving a `SLOAD` (2100 gas) every time they are accessed.

## 3. Storage Packing
The protocol uses efficient storage layouts to minimize the number of storage slots used.
- **Example**: `TokenConfig` struct in `PSM`.
  ```solidity
  struct TokenConfig {
      address priceFeed; // 20 bytes
      uint8 decimals;    // 1 byte
      uint16 feeBps;     // 2 bytes
      bool supported;    // 1 byte
  }
  ```
- **Benefit**: These fields fit into a single 32-byte storage slot, allowing them to be read/written in a single operation.

## 4. Efficient Loops and Mappings
- **Mapping vs Array**: User balances and collateral data are stored in mappings for O(1) access.
- **Array Length Caching**: In `_getAccountCollateralValueInUsd`, the length of `s_collateralTokens` is used in a loop. While the array is small, caching the length in memory prevents redundant `SLOAD` operations on the array length.

## 5. Internal Function Logic Sharing
Common logic is extracted into internal functions to reduce contract size and avoid code duplication.
- **Example**: `_calculateHealthFactor` and `_getAccountInformation` are used by both external view functions and internal state-changing functions.

## 6. Minimal State Changes
The protocol only updates state when absolutely necessary. For example, in `liquidate`, the health factor is checked at the beginning and end, but intermediate calculations are kept in memory.

## 7. Use of `external` vs `public`
Functions that are not called internally within the contract are marked as `external`.
- **Benefit**: `external` functions are more gas-efficient than `public` functions when receiving large arrays of data because they read directly from `calldata` instead of copying to `memory`.

## 8. Optimized Math
- **Precision**: Using `1e18` as a base for all calculations avoids the need for complex floating-point libraries.
- **Multiplication before Division**: Always performed to maintain maximum precision and avoid unnecessary rounding gas costs.
