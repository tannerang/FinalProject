// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { Test, console2 } from "forge-std/Test.sol";
import { FlashBot } from "../src/FlashBot.sol";
import '../src/interfaces/IUniswapV2Factory.sol';
import '../src/interfaces/IERC20.sol';
import '../src/interfaces/IUniswapV2Pair.sol';
import '../lib/library/SafeMath.sol';

contract FlashBotTest is Test {
    using SafeMath for uint;

    address public admin = makeAddr("admin");
    address user1 = makeAddr("user1");
    address user2 = makeAddr("user2");
    address constant WETH_ADDRESS = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant USDC_ADDRESS = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant AAVE_ADDRESS = 0x7Fc66500c84A76Ad7e9c93437bFc5Ac33E2DDaE9;
    address uniswapFactory = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
    address sushiswapFactory = 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac;
    address balancerTargetPool = 0x69d460e01070A7BA1bc363885bC8F4F0daa19Bf5;
    
    IERC20 public weth;
    IERC20 public aave;
    FlashBot public flashBot;
    //IUniswapV2Factory public uniswapV2Factory;

    function setUp() public {

        string memory rpc = vm.envString("MAINNET_RPC_URL");
        vm.createSelectFork(rpc);

        vm.startPrank(admin);
        flashBot = new FlashBot(WETH_ADDRESS);
        weth = IERC20(WETH_ADDRESS);
        aave = IERC20(AAVE_ADDRESS);
        deal(WETH_ADDRESS, user1, 100000 * 10 ** IERC20(weth).decimals());
        deal(AAVE_ADDRESS, user1, 100000 * 10 ** IERC20(aave).decimals());
    }

    function testGetProfit() public {

        address pool0 = IUniswapV2Factory(uniswapFactory).getPair(WETH_ADDRESS, AAVE_ADDRESS);
        address pool1 = IUniswapV2Factory(sushiswapFactory).getPair(WETH_ADDRESS, AAVE_ADDRESS);
        uint WETHAmountOut = 1 * 10 ** IERC20(weth).decimals();
        uint AAVEAmountOut = 100 * 10 ** IERC20(aave).decimals();
        console2.log("AAVEAmountOut:", AAVEAmountOut);
        console2.log("AAVE Bal before:", aave.balanceOf(user1));
        console2.log("WETH Bal before:", weth.balanceOf(user1));

        vm.startPrank(user1);
        (uint reserve0, uint reserve1,) = IUniswapV2Pair(pool0).getReserves();
        console2.log("reserve0:", reserve0, ",reserve1", reserve1);

        aave.approve(pool0, type(uint).max);
        weth.approve(pool0, type(uint).max);
        
        console2.log("token0:", IUniswapV2Pair(pool0).token0(), ",token1:",  IUniswapV2Pair(pool0).token1());
/*
        uint amountIn = getAmountIn(AAVEAmountOut, reserve1, reserve0); //In: WETH, Out: AAVE
        weth.transfer(pool0, amountIn);
        IUniswapV2Pair(pool0).swap(AAVEAmountOut, 0, user1, ""); // token0: AAVE, token1: WETH
*/
        uint amountIn = getAmountIn(WETHAmountOut, reserve0, reserve1); //In: AAVE, Out: WETH
        aave.transfer(pool0, amountIn);
        IUniswapV2Pair(pool0).swap(0, WETHAmountOut, user1, ""); // token0: AAVE, token1: WETH

        console2.log("swap done");
        vm.stopPrank();
        console2.log("AAVE Bal after:", aave.balanceOf(user1));
        console2.log("WETH Bal after:", weth.balanceOf(user1));

        (uint256 profit, address baseToken) = flashBot.getProfit(pool0, pool1);
        console2.log("Profit: ", profit, ",baseToken:", baseToken);
    }

    function testGetBPoolReserve() public {

    }

    // copy from UniswapV2Library
    // given an input amount of an asset and pair reserves, returns the maximum output amount of the other asset
    function getAmountOut(uint amountIn, uint reserveIn, uint reserveOut) internal pure returns (uint amountOut) {
        require(amountIn > 0, 'UniswapV2Library: INSUFFICIENT_INPUT_AMOUNT');
        require(reserveIn > 0 && reserveOut > 0, 'UniswapV2Library: INSUFFICIENT_LIQUIDITY');
        uint amountInWithFee = amountIn.mul(997);
        uint numerator = amountInWithFee.mul(reserveOut);
        uint denominator = reserveIn.mul(1000).add(amountInWithFee);
        amountOut = numerator / denominator;
    }

    // given an output amount of an asset and pair reserves, returns a required input amount of the other asset
    function getAmountIn(uint amountOut, uint reserveIn, uint reserveOut) internal pure returns (uint amountIn) {
        require(amountOut > 0, 'UniswapV2Library: INSUFFICIENT_OUTPUT_AMOUNT');
        require(reserveIn > 0 && reserveOut > 0, 'UniswapV2Library: INSUFFICIENT_LIQUIDITY');
        uint numerator = reserveIn.mul(amountOut).mul(1000);
        uint denominator = reserveOut.sub(amountOut).mul(997);
        amountIn = (numerator / denominator).add(1);
    }
}
