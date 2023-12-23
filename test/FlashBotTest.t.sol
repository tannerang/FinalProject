// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { Test, console2 } from "forge-std/Test.sol";
import { FlashBot } from "../src/FlashBot.sol";
import "../src/interfaces/IUniswapV2Factory.sol";
import "../src/interfaces/IERC20.sol";
import "../src/interfaces/IUniswapV2Pair.sol";
import "../src/interfaces/IBPool.sol";
import "../lib/library/SafeMath.sol";

contract FlashBotTest is Test {

    using SafeMath for uint;
    uint public constant BONE = 10**18;
    address public admin = makeAddr("admin");
    address user1 = makeAddr("user1");
    address user2 = makeAddr("user2");
    address constant WETH_ADDRESS = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant USDC_ADDRESS = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant AAVE_ADDRESS = 0x7Fc66500c84A76Ad7e9c93437bFc5Ac33E2DDaE9;
    address constant REQ_ADDRESS = 0x8f8221aFbB33998d8584A2B05749bA73c37a938a;
    address constant BAL_ADDRESS = 0xba100000625a3754423978a60c9317c58a424e3D;
    address uniswapFactory = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
    address sushiswapFactory = 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac;
    address targetBPool = 0xe867bE952ee17d2D294F2de62b13B9F4aF521e9a; // BAL / WETH
    address targetUniPool = 0xA70d458A4d9Bc0e6571565faee18a48dA5c0D593; // BAL / WETH
    address targetSushiPool = 0x9BffA3ce3E56d0d26447a45771FEc76bD4173022; // BAL / WETH

    //address targetBPool = 0x69d460e01070A7BA1bc363885bC8F4F0daa19Bf5; // REQ / WETH
    //address targetUniPool = 0x4a7d4BE868e0b811ea804fAF0D3A325c3A29a9ad; // REQ / WETH

    IERC20 public weth;
    IERC20 public aave;
    IERC20 public req;
    IERC20 public bal;
    FlashBot public flashBot;

    function setUp() public {

        string memory rpc = vm.envString("MAINNET_RPC_URL");
        vm.createSelectFork(rpc);

        vm.startPrank(admin);
        flashBot = new FlashBot(WETH_ADDRESS);
        weth = IERC20(WETH_ADDRESS);
        aave = IERC20(AAVE_ADDRESS);
        req = IERC20(REQ_ADDRESS);
        bal = IERC20(BAL_ADDRESS);

        deal(WETH_ADDRESS, user1, 100000 * 10 ** IERC20(weth).decimals());
        deal(AAVE_ADDRESS, user1, 100000 * 10 ** IERC20(aave).decimals());
        deal(REQ_ADDRESS, user1, 1000000000 * 10 ** IERC20(req).decimals());
        deal(BAL_ADDRESS, user1, 1000000000 * 10 ** IERC20(bal).decimals());
    }

    function testGetPool() public {
        address unipool = IUniswapV2Factory(uniswapFactory).getPair(WETH_ADDRESS, BAL_ADDRESS);
        address sushipool = IUniswapV2Factory(sushiswapFactory).getPair(WETH_ADDRESS, BAL_ADDRESS);
        console2.log("token0:", IUniswapV2Pair(unipool).token0(), ",token1:",  IUniswapV2Pair(unipool).token1());
        console2.log("token0:", IUniswapV2Pair(sushipool).token0(), ",token1:",  IUniswapV2Pair(sushipool).token1());
        console2.log("unipool address:", unipool, "sushipool address:", sushipool);
        assertEq(unipool, 0xA70d458A4d9Bc0e6571565faee18a48dA5c0D593);
        assertEq(sushipool, 0x9BffA3ce3E56d0d26447a45771FEc76bD4173022);
    }


    function testGetProfit() public {

        address pool0 = IUniswapV2Factory(uniswapFactory).getPair(WETH_ADDRESS, AAVE_ADDRESS);
        address pool1 = IUniswapV2Factory(sushiswapFactory).getPair(WETH_ADDRESS, AAVE_ADDRESS);
        uint WETHAmountOut = 1 * 10 ** IERC20(weth).decimals();
        console2.log("AAVE Bal before:", aave.balanceOf(user1));
        console2.log("WETH Bal before:", weth.balanceOf(user1));

        // Mock a large amount of swap in AAVE/WETH pair
        vm.startPrank(user1);
        aave.approve(pool0, type(uint).max);
        weth.approve(pool0, type(uint).max);
        (uint reserve0, uint reserve1,) = IUniswapV2Pair(pool0).getReserves();
        console2.log("reserve0:", reserve0, ",reserve1", reserve1);
        console2.log("token0:", IUniswapV2Pair(pool0).token0(), ",token1:",  IUniswapV2Pair(pool0).token1());

        uint amountIn = getAmountIn(WETHAmountOut, reserve0, reserve1); //In: AAVE, Out: WETH
        aave.transfer(pool0, amountIn);
        IUniswapV2Pair(pool0).swap(0, WETHAmountOut, user1, ""); // token0: AAVE, token1: WETH
        vm.stopPrank();

        console2.log("Swap done");
        console2.log("AAVE Bal after:", aave.balanceOf(user1));
        console2.log("WETH Bal after:", weth.balanceOf(user1));

        // Excute getProfit function (only for two unipools)
        (uint256 profit, address baseToken) = flashBot.getProfit(pool0, pool1);
        console2.log("Profit: ", profit, ",baseToken:", baseToken);
        assertGt(profit, 0);
    }

    function testBPoolBasicFunctions() public {
        
        address token0 = IUniswapV2Pair(targetUniPool).token0();
        address token1 = IUniswapV2Pair(targetUniPool).token1();
        console2.log("token0:", token0, ",token1:", token1); // token0: BAL, token1: WETH

        (uint uniReserve0, uint uniReserve1,) = IUniswapV2Pair(targetUniPool).getReserves();
        console2.log("uniReserve0:", uniReserve0, ",uniReserve1:", uniReserve1);

        uint BReserve0 = IBPool(targetBPool).getBalance(token0);
        uint BReserve1 = IBPool(targetBPool).getBalance(token1);
        console2.log("BReserve0:", BReserve0, ",BReserve1:", BReserve1);

        uint spotBPrice = IBPool(targetBPool).getSpotPrice(WETH_ADDRESS, BAL_ADDRESS);
        console2.log("spotBPrice(x WETH for 1 BAL):", spotBPrice);

        uint spotBPrice_ = IBPool(targetBPool).getSpotPrice(BAL_ADDRESS, WETH_ADDRESS);
        console2.log("spotBPrice(x BAL for 1 WETH):", spotBPrice_);

        uint wethDeWeight= IBPool(targetBPool).getDenormalizedWeight(WETH_ADDRESS);
        uint balDeWeight= IBPool(targetBPool).getDenormalizedWeight(BAL_ADDRESS);
        console2.log("wethDeWeight:", wethDeWeight, "balDeWeight:", balDeWeight);

        uint wethWeight= IBPool(targetBPool).getNormalizedWeight(WETH_ADDRESS);
        uint balWeight= IBPool(targetBPool).getNormalizedWeight(BAL_ADDRESS);
        console2.log("wethWeight:", wethWeight, "balWeight:", balWeight);
        
        uint spotUPrice = (uniReserve0/uniReserve1);
        console2.log("spotUPrice(x BAL for 1 WETH): $", spotUPrice);

        uint spotUPriceWithFee = calcSpotPrice(uniReserve1, 1e18, uniReserve0, 1e18, 3000000000000000);
        console2.log("spotUPriceWithFee(x WETH for 1 BAL): $", spotUPriceWithFee);

        uint spotUPriceWithoutFee = calcSpotPrice(uniReserve1, 1, uniReserve0, 1, 0);
        console2.log("spotUPriceWithoutFee(x WETH for 1 BAL): $", spotUPriceWithoutFee);

        uint swapFee = IBPool(targetBPool).getSwapFee();
        console2.log("swapFee:", swapFee);
    }

    function testArbitrageWithinUniPoolBPool() public {
        
        uint balanceBefore = weth.balanceOf(address(flashBot));
        
        // Mock a large amount of swap in BAL/WETH pair
        uint WETHAmountOut = 1 * 10 ** IERC20(weth).decimals();
        console2.log("BAL Bal before:", bal.balanceOf(user1));
        console2.log("WETH Bal before:", weth.balanceOf(user1));

        vm.startPrank(user1);
        (uint reserve0, uint reserve1,) = IUniswapV2Pair(targetUniPool).getReserves();
        console2.log("reserve0:", reserve0, ",reserve1", reserve1);

        bal.approve(targetUniPool, type(uint).max);
        weth.approve(targetUniPool, type(uint).max);
        console2.log("token0:", IUniswapV2Pair(targetUniPool).token0(), ",token1:",  IUniswapV2Pair(targetUniPool).token1());

        uint amountIn = getAmountIn(WETHAmountOut, reserve0, reserve1); //In: BAL, Out: WETH
        bal.transfer(targetUniPool, amountIn);
        IUniswapV2Pair(targetUniPool).swap(0, WETHAmountOut, user1, ""); // token0: BAL, token1: WETH
        vm.stopPrank();

        console2.log("Swap done");
        console2.log("BAL Bal after:", bal.balanceOf(user1));
        console2.log("WETH Bal after:", weth.balanceOf(user1));

        // Excute Arbitrage
        bool success = flashBot.excuteArbitrageWithinUniPoolBPool(targetBPool, targetUniPool);

        uint balanceAfter = weth.balanceOf(address(flashBot));
        console2.log("balanceBefore:", balanceBefore);
        console2.log("balanceAfter:", balanceAfter);
        console2.log("finalProfit:", balanceAfter-balanceBefore);
        assertGt(balanceAfter-balanceBefore, 0);
    }

    function testArbitrageWithinUniPools() public {
        
        uint balanceBefore = weth.balanceOf(address(flashBot));
                
        // Mock a large amount of swap in BAL/WETH pair
        uint BALAmountOut = 100 * 10 ** IERC20(bal).decimals();
        console2.log("BAL Bal before:", bal.balanceOf(user1));
        console2.log("WETH Bal before:", weth.balanceOf(user1));

        vm.startPrank(user1);
        (uint reserve0, uint reserve1,) = IUniswapV2Pair(targetUniPool).getReserves();
        console2.log("reserve0:", reserve0, ",reserve1", reserve1);

        bal.approve(targetUniPool, type(uint).max);
        weth.approve(targetUniPool, type(uint).max);
        console2.log("token0:", IUniswapV2Pair(targetUniPool).token0(), ",token1:",  IUniswapV2Pair(targetUniPool).token1());

        uint amountIn = getAmountIn(BALAmountOut, reserve1, reserve0); //In: BAL, Out: WETH
        weth.transfer(targetUniPool, amountIn);
        IUniswapV2Pair(targetUniPool).swap(BALAmountOut, 0, user1, ""); // token0: BAL, token1: WETH
        vm.stopPrank();

        console2.log("Swap done");
        console2.log("BAL Bal after:", bal.balanceOf(user1));
        console2.log("WETH Bal after:", weth.balanceOf(user1));
        
        // Excute Arbitrage
        bool success = flashBot.excuteArbitrageWithinUniPools(targetSushiPool, targetUniPool);

        uint balanceAfter = weth.balanceOf(address(flashBot));
        console2.log("balanceBefore:", balanceBefore);
        console2.log("balanceAfter:", balanceAfter);
        console2.log("finalProfit:", balanceAfter-balanceBefore);
        assertGt(balanceAfter-balanceBefore, 0);
    }

    // copy from UniswapV2Library
    function getAmountOut(uint amountIn, uint reserveIn, uint reserveOut) internal pure returns (uint amountOut) {
        require(amountIn > 0, 'UniswapV2Library: INSUFFICIENT_INPUT_AMOUNT');
        require(reserveIn > 0 && reserveOut > 0, 'UniswapV2Library: INSUFFICIENT_LIQUIDITY');
        uint amountInWithFee = amountIn.mul(997);
        uint numerator = amountInWithFee.mul(reserveOut);
        uint denominator = reserveIn.mul(1000).add(amountInWithFee);
        amountOut = numerator / denominator;
    }

    // copy from UniswapV2Library
    function getAmountIn(uint amountOut, uint reserveIn, uint reserveOut) internal pure returns (uint amountIn) {
        require(amountOut > 0, 'UniswapV2Library: INSUFFICIENT_OUTPUT_AMOUNT');
        require(reserveIn > 0 && reserveOut > 0, 'UniswapV2Library: INSUFFICIENT_LIQUIDITY');
        uint numerator = reserveIn.mul(amountOut).mul(1000);
        uint denominator = reserveOut.sub(amountOut).mul(997);
        amountIn = (numerator / denominator).add(1);
    }

    // copy from BNum
    function bdiv(uint a, uint b)
        internal pure
        returns (uint)
    {
        require(b != 0, "ERR_DIV_ZERO");
        uint c0 = a * BONE;
        require(a == 0 || c0 / a == BONE, "ERR_DIV_INTERNAL"); // bmul overflow
        uint c1 = c0 + (b / 2);
        require(c1 >= c0, "ERR_DIV_INTERNAL"); //  badd require
        uint c2 = c1 / b;
        return c2;
    }

    // copy from BNum
    function bmul(uint a, uint b)
        internal pure
        returns (uint)
    {
        uint c0 = a * b;
        require(a == 0 || c0 / a == b, "ERR_MUL_OVERFLOW");
        uint c1 = c0 + (BONE / 2);
        require(c1 >= c0, "ERR_MUL_OVERFLOW");
        uint c2 = c1 / BONE;
        return c2;
    }

    // copy from BNum
    function bsub(uint a, uint b)
        internal pure
        returns (uint)
    {
        (uint c, bool flag) = bsubSign(a, b);
        require(!flag, "ERR_SUB_UNDERFLOW");
        return c;
    }

    // copy from BNum
    function bsubSign(uint a, uint b)
        internal pure
        returns (uint, bool)
    {
        if (a >= b) {
            return (a - b, false);
        } else {
            return (b - a, true);
        }
    }

    // copy from BMath
    function calcSpotPrice(
        uint tokenBalanceIn,
        uint tokenWeightIn,
        uint tokenBalanceOut,
        uint tokenWeightOut,
        uint swapFee
    )
        public pure
        returns (uint spotPrice)
    {
        uint numer = bdiv(tokenBalanceIn, tokenWeightIn);
        uint denom = bdiv(tokenBalanceOut, tokenWeightOut);
        uint ratio = bdiv(numer, denom);
        uint scale = bdiv(BONE, bsub(BONE, swapFee));
        return  (spotPrice = bmul(ratio, scale));
    }
}
