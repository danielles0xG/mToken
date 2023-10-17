// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

/*
* @notice Custom Math Lib
 * @title WadRayMath & MathUtils library
 * @author Morpho Labs. & Aave
 * @notice Optimized version of Aave V3 math library WadRayMath to conduct wad and ray manipulations: https://github.com/aave/aave-v3-core/blob/master/contracts/protocol/libraries/math/sol
 * @title MathUtils library

 * @notice Provides functions to perform linear and compounded interest calculations
 */
library MathUtils {
    /* CONSTANTS */

    // Only direct number constants and references to such constants are supported by inline assembly.
    uint256 internal constant WAD = 1e18;
    uint256 internal constant HALF_WAD = 0.5e18;
    uint256 internal constant WAD_MINUS_ONE = 1e18 - 1;
    uint256 internal constant RAY = 1e27;
    uint256 internal constant HALF_RAY = 0.5e27;
    uint256 internal constant RAY_MINUS_ONE = 1e27 - 1;
    uint256 internal constant RAY_WAD_RATIO = 1e9;
    uint256 internal constant HALF_RAY_WAD_RATIO = 0.5e9;
    uint256 internal constant MAX_UINT256 = 2 ** 256 - 1;
    uint256 internal constant MAX_UINT256_MINUS_HALF_WAD = 2 ** 256 - 1 - 0.5e18;
    uint256 internal constant MAX_UINT256_MINUS_HALF_RAY = 2 ** 256 - 1 - 0.5e27;
    uint256 internal constant MAX_UINT256_MINUS_WAD_MINUS_ONE = 2 ** 256 - 1 - (1e18 - 1);
    uint256 internal constant MAX_UINT256_MINUS_RAY_MINUS_ONE = 2 ** 256 - 1 - (1e27 - 1);

    /// @dev Executes the ray-based multiplication of 2 numbers, rounded half up.
    /// @param x Ray.
    /// @param y Ray.
    /// @return z The result of x * y, in ray.
    function rayMul(uint256 x, uint256 y) internal pure returns (uint256 z) {
        // Overflow if
        //     x * y + HALF_RAY > type(uint256).max
        // <=> x * y > type(uint256).max - HALF_RAY
        // <=> y > 0 and x > (type(uint256).max - HALF_RAY) / y
        assembly {
            if mul(y, gt(x, div(MAX_UINT256_MINUS_HALF_RAY, y))) { revert(0, 0) }

            z := div(add(mul(x, y), HALF_RAY), RAY)
        }
    }

    /// @dev Converts ray down to wad.
    /// @param x Ray.
    /// @return y = x converted to wad, rounded half up to the nearest wad.
    function rayToWad(uint256 x) internal pure returns (uint256 y) {
        assembly {
            // If x % RAY_WAD_RATIO >= HALF_RAY_WAD_RATIO, round up.
            y := add(div(x, RAY_WAD_RATIO), iszero(lt(mod(x, RAY_WAD_RATIO), HALF_RAY_WAD_RATIO)))
        }
    }

    /// @notice Computes the ray-based weighted average (x * (1 - weight) + y * weight), rounded half up.
    /// @param x The first value, with a weight of 1 - weight.
    /// @param y The second value, with a weight of weight.
    /// @param weight The weight of y, and complement of the weight of x (in ray).
    /// @return z The result of the ray-based weighted average.
    function rayWeightedAvg(uint256 x, uint256 y, uint256 weight) internal pure returns (uint256 z) {
        // 1. Underflow if
        //        weight > RAY
        // 2. Overflow if
        //        y * weight + HALF_RAY > type(uint256).max
        //    <=> weight > 0 and y > (type(uint256).max - HALF_RAY) / weight
        // 3. Overflow if
        //        x * (RAY - weight) + y * weight + HALF_RAY > type(uint256).max
        //    <=> x * (RAY - weight) > type(uint256).max - HALF_RAY - y * weight
        //    <=> RAY > weight and x > (type(uint256).max - HALF_RAY - y * weight) / (RAY - weight)
        assembly {
            z := sub(RAY, weight) // Temporary assignment to save gas.

            if or(
                gt(weight, RAY),
                or(
                    mul(weight, gt(y, div(MAX_UINT256_MINUS_HALF_RAY, weight))),
                    mul(z, gt(x, div(sub(MAX_UINT256_MINUS_HALF_RAY, mul(y, weight)), z)))
                )
            ) { revert(0, 0) }

            z := div(add(add(mul(x, z), mul(y, weight)), HALF_RAY), RAY)
        }
    }

    /// @dev Ignoring leap years
    uint256 internal constant SECONDS_PER_YEAR = 365 days;

    /**
     * @dev Function to calculate the interest accumulated using a linear interest rate formula
     * @param rate The interest rate, in ray
     * @param lastUpdateTimestamp The timestamp of the last update of the interest
     * @return The interest rate linearly accumulated during the timeDelta, in ray
     */
    function calculateLinearInterest(uint256 rate, uint40 lastUpdateTimestamp) internal view returns (uint256) {
        //solium-disable-next-line
        uint256 result = rate * (block.timestamp - uint256(lastUpdateTimestamp));
        unchecked {
            result = result / SECONDS_PER_YEAR;
        }

        return RAY + result;
    }

    /**
     * @dev Function to calculate the interest using a compounded interest rate formula
     * To avoid expensive exponentiation, the calculation is performed using a binomial approximation:
     *
     *  (1+x)^n = 1+n*x+[n/2*(n-1)]*x^2+[n/6*(n-1)*(n-2)*x^3...
     *
     * The approximation slightly underpays liquidity providers and undercharges borrowers, with the advantage of great
     * gas cost reductions. The whitepaper contains reference to the approximation and a table showing the margin of
     * error per different time periods
     *
     * @param rate The interest rate, in ray
     * @param lastUpdateTimestamp The timestamp of the last update of the interest
     * @return The interest rate compounded during the timeDelta, in ray
     */
    function calculateCompoundedInterest(uint256 rate, uint40 lastUpdateTimestamp, uint256 currentTimestamp)
        internal
        pure
        returns (uint256)
    {
        //solium-disable-next-line
        uint256 exp = currentTimestamp - uint256(lastUpdateTimestamp);

        if (exp == 0) {
            return RAY;
        }

        uint256 expMinusOne;
        uint256 expMinusTwo;
        uint256 basePowerTwo;
        uint256 basePowerThree;
        unchecked {
            expMinusOne = exp - 1;

            expMinusTwo = exp > 2 ? exp - 2 : 0;

            basePowerTwo = rayMul(rate, rate) / (SECONDS_PER_YEAR * SECONDS_PER_YEAR);
            basePowerThree = rayMul(basePowerTwo, rate) / SECONDS_PER_YEAR;
        }

        uint256 secondTerm = exp * expMinusOne * basePowerTwo;
        unchecked {
            secondTerm /= 2;
        }
        uint256 thirdTerm = exp * expMinusOne * expMinusTwo * basePowerThree;
        unchecked {
            thirdTerm /= 6;
        }

        return RAY + (rate * exp) / SECONDS_PER_YEAR + secondTerm + thirdTerm;
    }

    /**
     * @dev Calculates the compounded interest between the timestamp of the last update and the current block timestamp
     * @param rate The interest rate (in ray)
     * @param lastUpdateTimestamp The timestamp from which the interest accumulation needs to be calculated
     * @return The interest rate compounded between lastUpdateTimestamp and current block timestamp, in ray
     */
    function calculateCompoundedInterest(uint256 rate, uint40 lastUpdateTimestamp) internal view returns (uint256) {
        return calculateCompoundedInterest(rate, lastUpdateTimestamp, block.timestamp);
    }

    /// @notice Calculates floor(a×b÷denominator) with full precision. Throws if result overflows a uint256 or denominator == 0
    /// @param a The multiplicand
    /// @param b The multiplier
    /// @param denominator The divisor
    /// @return result The 256-bit result
    /// @dev Credit to Remco Bloemen under MIT license https://xn--2-umb.com/21/muldiv
    function mulDiv(uint256 a, uint256 b, uint256 denominator) internal pure returns (uint256 result) {
        // 512-bit multiply [prod1 prod0] = a * b
        // Compute the product mod 2**256 and mod 2**256 - 1
        // then use the Chinese Remainder Theorem to reconstruct
        // the 512 bit result. The result is stored in two 256
        // variables such that product = prod1 * 2**256 + prod0
        uint256 prod0; // Least significant 256 bits of the product
        uint256 prod1; // Most significant 256 bits of the product
        assembly {
            let mm := mulmod(a, b, not(0))
            prod0 := mul(a, b)
            prod1 := sub(sub(mm, prod0), lt(mm, prod0))
        }

        // Handle non-overflow cases, 256 by 256 division
        if (prod1 == 0) {
            require(denominator > 0);
            assembly {
                result := div(prod0, denominator)
            }
            return result;
        }

        // Make sure the result is less than 2**256.
        // Also prevents denominator == 0
        require(denominator > prod1);

        ///////////////////////////////////////////////
        // 512 by 256 division.
        ///////////////////////////////////////////////

        // Make division exact by subtracting the remainder from [prod1 prod0]
        // Compute remainder using mulmod
        uint256 remainder;
        assembly {
            remainder := mulmod(a, b, denominator)
        }
        // Subtract 256 bit number from 512 bit number
        assembly {
            prod1 := sub(prod1, gt(remainder, prod0))
            prod0 := sub(prod0, remainder)
        }

        // Factor powers of two out of denominator
        // Compute largest power of two divisor of denominator.
        // Always >= 1.

        uint256 twos = uint256(-int256(denominator)) & denominator;

        // Divide denominator by power of two
        assembly {
            denominator := div(denominator, twos)
        }

        // Divide [prod1 prod0] by the factors of two
        assembly {
            prod0 := div(prod0, twos)
        }
        // Shift in bits from prod1 into prod0. For this we need
        // to flip `twos` such that it is 2**256 / twos.
        // If twos is zero, then it becomes one
        assembly {
            twos := add(div(sub(0, twos), twos), 1)
        }
        prod0 |= prod1 * twos;

        // Invert denominator mod 2**256
        // Now that denominator is an odd number, it has an inverse
        // modulo 2**256 such that denominator * inv = 1 mod 2**256.
        // Compute the inverse by starting with a seed that is correct
        // correct for four bits. That is, denominator * inv = 1 mod 2**4
        uint256 inv = (3 * denominator) ^ 2;
        // Now use Newton-Raphson iteration to improve the precision.
        // Thanks to Hensel's lifting lemma, this also works in modular
        // arithmetic, doubling the correct bits in each step.
        inv *= 2 - denominator * inv; // inverse mod 2**8
        inv *= 2 - denominator * inv; // inverse mod 2**16
        inv *= 2 - denominator * inv; // inverse mod 2**32
        inv *= 2 - denominator * inv; // inverse mod 2**64
        inv *= 2 - denominator * inv; // inverse mod 2**128
        inv *= 2 - denominator * inv; // inverse mod 2**256

        // Because the division is now exact we can divide by multiplying
        // with the modular inverse of denominator. This will give us the
        // correct result modulo 2**256. Since the precoditions guarantee
        // that the outcome is less than 2**256, this is the final result.
        // We don't need to compute the high bits of the result and prod1
        // is no longer required.
        result = prod0 * inv;
        return result;
    }

    /// @notice Calculates ceil(a×b÷denominator) with full precision. Throws if result overflows a uint256 or denominator == 0
    /// @param a The multiplicand
    /// @param b The multiplier
    /// @param denominator The divisor
    /// @return result The 256-bit result
    function mulDivRoundingUp(uint256 a, uint256 b, uint256 denominator) internal pure returns (uint256 result) {
        result = mulDiv(a, b, denominator);
        if (mulmod(a, b, denominator) > 0) {
            require(result < type(uint256).max);
            result++;
        }
    }
}
