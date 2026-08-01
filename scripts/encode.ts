/**
 * encode.ts
 * Helper functions to encode HTTP requests and ONNX tensors for Ritual precompiles.
 * Uses viem for clean encoding.
 *
 * Install: pnpm add viem
 */

import { encodeAbiParameters, parseAbiParameters } from 'viem';

// ---------------------------------------------------------------------------
// HTTP Precompile Input Encoding (for reference / future use)
// ---------------------------------------------------------------------------
export function encodeHttpRequest(
  url: string,
  method: string,
  headers: string,
  body: string
) {
  // The precompile expects the raw values — no extra ABI encoding needed
  // when calling directly from Solidity.
  return { url, method, headers, body };
}

// ---------------------------------------------------------------------------
// ONNX Tensor Encoding (RitualTensor format)
// ---------------------------------------------------------------------------
/**
 * Encodes an array of APYs and volatilities into the simple packed format
 * expected by the current LiveYieldOracle._encodeYieldTensor placeholder.
 *
 * In production you would use the official Ritual tensor encoding.
 */
export function encodeYieldTensor(apys: number[], vols: number[]): `0x${string}` {
  if (apys.length !== vols.length) {
    throw new Error('APY and volatility arrays must have the same length');
  }

  let data = '0x' as `0x${string}`;

  for (let i = 0; i < apys.length; i++) {
    const apyEncoded = apys[i].toString(16).padStart(8, '0');
    const volEncoded = vols[i].toString(16).padStart(8, '0');
    data = (data + apyEncoded + volEncoded) as `0x${string}`;
  }

  return data;
}

/**
 * Example usage:
 *
 * const tensor = encodeYieldTensor([850, 920, 780], [120, 95, 150]);
 * console.log(tensor);
 */