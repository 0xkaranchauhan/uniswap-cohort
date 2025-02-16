// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";

import {Deployers} from "@uniswap/v4-core/test/utils/Deployers.sol";
import {PoolSwapTest} from "v4-core/test/PoolSwapTest.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";

import {PoolManager} from "v4-core/PoolManager.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";

import {Currency, CurrencyLibrary} from "v4-core/types/Currency.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {SqrtPriceMath} from "v4-core/libraries/SqrtPriceMath.sol";
import {LiquidityAmounts} from "@uniswap/v4-core/test/utils/LiquidityAmounts.sol";

import "forge-std/console.sol";
import {PointsHook} from "../../src/4/PointsHook.sol";

contract PointsHookTest is Test, Deployers {
    PointsHook hook;
    MockERC20 token;

    function setUp() public {
        // 1. We need to deploy Uniswap V4 itself

        deployFreshManagerAndRouters();

        // 2. any auxilliary contracts (in our case meme tokens)
        token = new MockERC20("MEME COIN", "MEME", 18);
        token.mint(address(this), 1000 ether);

        // 3. deployCodeTo - allows you to deploy a contract at any arbitrary address of your choice
        uint160 flags = uint160(
            Hooks.AFTER_SWAP_FLAG | Hooks.AFTER_ADD_LIQUIDITY_FLAG
        );

        address hookAddress = address(flags);

        deployCodeTo(
            "PointsHook.sol",
            abi.encode(manager, "Points Token", "TEST_POINTS"),
            address(flags)
        );

        hook = PointsHook(hookAddress);

        // 4. create a pool + attach our hook to the pool
        (key, ) = initPool(
            Currency.wrap(address(0)),
            Currency.wrap(address(token)),
            hook,
            3000,
            SQRT_PRICE_1_1
        );

        token.approve(address(swapRouter), type(uint256).max);
        token.approve(address(modifyLiquidityRouter), type(uint256).max);
    }

    function test_addLiquidityAndSwap() public {
        uint256 pointsBalanceOriginal = hook.balanceOf(address(this));

        // Set user address in hook data
        bytes memory hookData = abi.encode(address(this));

        uint160 sqrtPriceAtTickLower = TickMath.getSqrtPriceAtTick(-60);
        // uint160 sqrtPriceAtTickUpper = TickMath.getSqrtPriceAtTick(60);

        uint256 ethToAdd = 0.1 ether;
        uint128 liquidityDelta = LiquidityAmounts.getLiquidityForAmount0(
            sqrtPriceAtTickLower,
            SQRT_PRICE_1_1,
            ethToAdd
        );
        // uint256 tokenToAdd = LiquidityAmounts.getAmount1ForLiquidity(
        //     sqrtPriceAtTickUpper,
        //     SQRT_PRICE_1_1,
        //     liquidityDelta
        // );

        modifyLiquidityRouter.modifyLiquidity{value: ethToAdd}(
            key,
            IPoolManager.ModifyLiquidityParams({
                tickLower: -60,
                tickUpper: 60,
                liquidityDelta: int256(uint256(liquidityDelta)),
                salt: bytes32(0)
            }),
            hookData
        );
        uint256 pointsBalanceAfterAddLiquidity = hook.balanceOf(address(this));

        assertApproxEqAbs(
            pointsBalanceAfterAddLiquidity - pointsBalanceOriginal,
            0.1 ether,
            0.001 ether // error margin for precision loss
        );

        // Now we swap
        // We will swap 0.001 ether for tokens
        // We should get 20% of 0.001 * 10**18 points
        // = 2 * 10**14
        swapRouter.swap{value: 0.001 ether}(
            key,
            IPoolManager.SwapParams({
                zeroForOne: true,
                amountSpecified: -0.001 ether, // Exact input for output swap
                sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
            }),
            PoolSwapTest.TestSettings({
                takeClaims: false,
                settleUsingBurn: false
            }),
            hookData
        );
        uint256 pointsBalanceAfterSwap = hook.balanceOf(address(this));
        assertEq(
            pointsBalanceAfterSwap - pointsBalanceAfterAddLiquidity,
            2 * 10 ** 14
        );
    }
}
