// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "balancer-v2-monorepo/pkg/interfaces/contracts/vault/IVault.sol";
import "balancer-v2-monorepo/pkg/interfaces/contracts/vault/IFlashLoanRecipient.sol";
import "./interfaces/IUniswapV2Pair.sol";
import "./interfaces/IBPool.sol";
import { console2 } from "forge-std/Test.sol";

struct OrderedReserves {
    uint256 a1; // base asset
    uint256 b1;
    uint256 a2;
    uint256 b2;
}

struct DiffPoolInfo {
    address baseToken;
    address quoteToken;
    bool baseTokenSmaller;
    address lowerPool; // pool with lower price, denominated in quote asset
    address higherPool; // pool with higher price, denominated in quote asset
    uint spotUPrice;
    uint spotBPrice;
}

struct SamePoolInfo {
    address baseToken;
    address quoteToken;
    bool baseTokenSmaller;
    address lowerPool; // pool with lower price, denominated in quote asset
    address higherPool; // pool with higher price, denominated in quote asset
    uint price0;
    uint price1;
}

struct CallbackData {
    address debtPool;
    address targetPool;
    bool debtTokenSmaller;
    address borrowedToken;
    address debtToken;
    uint256 debtAmount;
    uint256 debtTokenOutAmount;
    uint256 borrowAmount;
    uint256 spotUPrice;
    uint256 spotBPrice;
}

contract FlashBot is IFlashLoanRecipient, Ownable {

    using EnumerableSet for EnumerableSet.AddressSet;

    // BALANCER VAULT
    address public VAULT_ADDRESS = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;
    IVault private vault = IVault(VAULT_ADDRESS);
    
    // BCONST USED
    uint public constant BONE = 10**18;

    // AVAILABLE BASE TOKENS
    EnumerableSet.AddressSet baseTokens;

    // INIT BASE TOKEN
    address public WETH;

    event Withdrawn(address indexed to, uint256 indexed value);
    event BaseTokenAdded(address indexed token);
    event BaseTokenRemoved(address indexed token);

    constructor(address _WETH) Ownable(msg.sender){
        WETH = _WETH;
        baseTokens.add(_WETH);
    }

    receive() external payable {}

    function withdraw() external onlyOwner {
        uint256 balance = address(this).balance;
        if (balance > 0) {
            payable(owner()).transfer(balance);
            emit Withdrawn(owner(), balance);
        }

        for (uint256 i = 0; i < baseTokens.length(); i++) {
            address token = baseTokens.at(i);
            balance = IERC20(token).balanceOf(address(this));
            if (balance > 0) {
                // do not use safe transfer here to prevents revert by any shitty token
                IERC20(token).transfer(owner(), balance);
            }
        }
    }

    function addBaseToken(address token) external onlyOwner {
        baseTokens.add(token);
        emit BaseTokenAdded(token);
    }

    function removeBaseToken(address token) external onlyOwner {
        uint256 balance = IERC20(token).balanceOf(address(this));
        if (balance > 0) {
            // do not use safe transfer to prevents revert by any shitty token
            IERC20(token).transfer(owner(), balance);
        }
        baseTokens.remove(token);
        emit BaseTokenRemoved(token);
    }

    function getBaseTokens() external view returns (address[] memory tokens) {
        uint256 length = baseTokens.length();
        tokens = new address[](length);
        for (uint256 i = 0; i < length; i++) {
            tokens[i] = baseTokens.at(i);
        }
    }

    function baseTokensContains(address token) public view returns (bool) {
        return baseTokens.contains(token);
    }

    function isbaseTokenSmaller(address pool0, address pool1)
        internal
        view
        returns (
            bool baseSmaller,
            address baseToken,
            address quoteToken
        )
    {
        require(pool0 != pool1, 'Same pair address');
        (address pool0Token0, address pool0Token1) = (IUniswapV2Pair(pool0).token0(), IUniswapV2Pair(pool0).token1());
        (address pool1Token0, address pool1Token1) = (IUniswapV2Pair(pool1).token0(), IUniswapV2Pair(pool1).token1());
        require(pool0Token0 < pool0Token1 && pool1Token0 < pool1Token1, 'Non standard uniswap AMM pair');
        require(pool0Token0 == pool1Token0 && pool0Token1 == pool1Token1, 'Require same token pair');
        require(baseTokensContains(pool0Token0) || baseTokensContains(pool0Token1), 'No base token in pair');

        (baseSmaller, baseToken, quoteToken) = baseTokensContains(pool0Token0)
            ? (true, pool0Token0, pool0Token1)
            : (false, pool0Token1, pool0Token0);
    }

   function isbaseTokenSmallerWithBPool(address uniPool)
        internal
        view
        returns (
            bool baseSmaller,
            address baseToken,
            address quoteToken
        )
    {
        (address uniPoolToken0, address uniPoolToken1) = (IUniswapV2Pair(uniPool).token0(), IUniswapV2Pair(uniPool).token1());
        require(uniPoolToken0 < uniPoolToken1, 'Non standard uniswap AMM pair');
        require(baseTokensContains(uniPoolToken0) || baseTokensContains(uniPoolToken1), 'No base token in pair');

        (baseSmaller, baseToken, quoteToken) = baseTokensContains(uniPoolToken0)
            ? (true, uniPoolToken0, uniPoolToken1)
            : (false, uniPoolToken1, uniPoolToken0);
    }

    function getOrderedReserves(
        address pool0,
        address pool1,
        bool baseTokenSmaller
    )
        internal
        view
        returns (
            address lowerPool,
            address higherPool,
            uint price0,
            uint price1,
            OrderedReserves memory orderedReserves
        )
    {
        (uint256 pool0Reserve0, uint256 pool0Reserve1, ) = IUniswapV2Pair(pool0).getReserves();
        (uint256 pool1Reserve0, uint256 pool1Reserve1, ) = IUniswapV2Pair(pool1).getReserves();

        (price0, price1) =
            baseTokenSmaller
                ? (pool0Reserve0/(pool0Reserve1), pool1Reserve0/(pool1Reserve1))
                : (pool0Reserve1/(pool0Reserve0), pool1Reserve1/(pool1Reserve0));

        // get a1, b1, a2, b2 with following rule:
        // 1. (a1, b1) represents the pool with lower price, denominated in quote asset token
        // 2. (a1, a2) are the base tokens in two pools
        if (price0 <= price1) {
            (lowerPool, higherPool) = (pool0, pool1);
            (orderedReserves.a1, orderedReserves.b1, orderedReserves.a2, orderedReserves.b2) = baseTokenSmaller
                ? (pool0Reserve0, pool0Reserve1, pool1Reserve0, pool1Reserve1)
                : (pool0Reserve1, pool0Reserve0, pool1Reserve1, pool1Reserve0);
        } else {
            (lowerPool, higherPool) = (pool1, pool0);
            (orderedReserves.a1, orderedReserves.b1, orderedReserves.a2, orderedReserves.b2) = baseTokenSmaller
                ? (pool1Reserve0, pool1Reserve1, pool0Reserve0, pool0Reserve1)
                : (pool1Reserve1, pool1Reserve0, pool0Reserve1, pool0Reserve0);
        }
        console2.log('Borrow from pool:', lowerPool);
        console2.log('Sell to pool:', higherPool);
    }

    function getOrderedReservesWithBPool(
        address bpool,
        address upool,
        bool baseTokenSmaller
    )
        internal
        view
        returns (
            address lowerPool,
            address higherPool,
            uint spotBPrice,
            uint spotUPrice,
            OrderedReserves memory orderedReserves
        )
    {
        (uint uniReserve0, uint uniReserve1,) = IUniswapV2Pair(upool).getReserves();
        console2.log("uniReserve0:", uniReserve0, ",uniReserve1", uniReserve1);

        (address token0, address token1) = (IUniswapV2Pair(upool).token0(), IUniswapV2Pair(upool).token1());
        (uint BReserve0, uint BReserve1) = (IBPool(bpool).getBalance(token0), IBPool(bpool).getBalance(token1));
        
        (spotBPrice, spotUPrice) =
            baseTokenSmaller
                ? (IBPool(bpool).getSpotPrice(token0, token1), calcSpotPrice(uniReserve0, 1e18, uniReserve1, 1e18, 3000000000000000))
                : (IBPool(bpool).getSpotPrice(token1, token0), calcSpotPrice(uniReserve1, 1e18, uniReserve0, 1e18, 3000000000000000));

        // get a1, b1, a2, b2 with following rule:
        // 1. (a1, b1) represents the pool with lower price, denominated in quote asset token
        // 2. (a1, a2) are the base tokens in two pools
        if (spotUPrice > spotBPrice) {
            (lowerPool, higherPool) = (bpool, upool);
            (orderedReserves.a1, orderedReserves.b1, orderedReserves.a2, orderedReserves.b2) = baseTokenSmaller
                ? (BReserve0, BReserve1, uniReserve0, uniReserve1)
                : (BReserve1, BReserve0, uniReserve1, uniReserve0);
        } else {
            (lowerPool, higherPool) = (upool, bpool);
            (orderedReserves.a1, orderedReserves.b1, orderedReserves.a2, orderedReserves.b2) = baseTokenSmaller
                ? (uniReserve0, uniReserve1, BReserve0, BReserve1)
                : (uniReserve1, uniReserve0, BReserve1, BReserve0);
        }
    }

    function calcBaseTokenOutAmount(
        OrderedReserves memory orderedReserves, 
        DiffPoolInfo memory info, 
        address targetBPool, 
        address targetUniPool, 
        uint borrowAmount
    ) 
        internal 
        returns (
            uint baseTokenOutAmount, 
            uint debtAmount, 
            uint profitAmount
        ) 
    {
        (uint baseTokenWeight, uint quoteTokenWeight) = (IBPool(targetBPool).getNormalizedWeight(info.baseToken), IBPool(targetBPool).getNormalizedWeight(info.quoteToken));

        if (info.spotUPrice > info.spotBPrice) {
            // borrow quote token on lower price pool, calculate how much debt we need to pay demoninated in base token
            debtAmount = IBPool(targetBPool).calcInGivenOut(
                orderedReserves.a1, 
                baseTokenWeight,
                orderedReserves.b1, 
                quoteTokenWeight,
                borrowAmount,
                IBPool(targetBPool).getSwapFee()
            );
            // sell borrowed quote token on higher price pool, calculate how much base token we can get
            baseTokenOutAmount = getAmountOut(borrowAmount, orderedReserves.b2, orderedReserves.a2);
            require(baseTokenOutAmount > debtAmount, 'Arbitrage fail, no profit (spotUPrice > spotBPrice)');
            console2.log('Profit (spotUPrice > spotBPrice):', (baseTokenOutAmount - debtAmount));
            profitAmount = baseTokenOutAmount - debtAmount;
        } else {
            // borrow quote token on lower price pool, calculate how much debt we need to pay demoninated in base token
            debtAmount = getAmountIn(borrowAmount, orderedReserves.a1, orderedReserves.b1);
            // sell borrowed quote token on higher price pool, calculate how much base token we can get
            baseTokenOutAmount = IBPool(targetBPool).calcOutGivenIn(
                orderedReserves.b2, 
                quoteTokenWeight,
                orderedReserves.a2, 
                baseTokenWeight,
                borrowAmount,
                IBPool(targetBPool).getSwapFee()
            );                
            require(baseTokenOutAmount > debtAmount, 'Arbitrage fail, no profit (spotUPrice < spotBPrice)');
            console2.log('Profit (spotUPrice < spotBPrice):', (baseTokenOutAmount - debtAmount));
            profitAmount = baseTokenOutAmount - debtAmount;
        }
    }

    function setCallbackData(
        OrderedReserves memory orderedReserves, 
        DiffPoolInfo memory info, 
        uint debtAmount, 
        uint baseTokenOutAmount, 
        uint borrowAmount
    ) 
        internal 
        returns (
            bytes memory data
        ) 
    {
        CallbackData memory callbackData;

        callbackData.debtPool = info.lowerPool;
        callbackData.targetPool = info.higherPool;
        callbackData.debtTokenSmaller = info.baseTokenSmaller;
        callbackData.borrowedToken = info.quoteToken;
        callbackData.debtToken = info.baseToken;
        callbackData.debtAmount = debtAmount;
        callbackData.debtTokenOutAmount = baseTokenOutAmount;
        callbackData.borrowAmount = borrowAmount;
        callbackData.spotUPrice = info.spotUPrice;
        callbackData.spotBPrice = info.spotBPrice;

        data = abi.encode(callbackData);
    }

    function excuteArbitrageWithinUniPoolBPool(
        address targetBPool, 
        address targetUniPool
    ) 
        external 
        returns (
            bool success
        ) 
    {
        // Check if base token smaller than quote token
        DiffPoolInfo memory info;
        (info.baseTokenSmaller, info.baseToken, info.quoteToken) = isbaseTokenSmallerWithBPool(targetUniPool);

        // Get two pools reserves in order
        OrderedReserves memory orderedReserves;
        (info.lowerPool, info.higherPool, info.spotBPrice, info.spotUPrice, orderedReserves) = 
            getOrderedReservesWithBPool(targetBPool, targetUniPool, info.baseTokenSmaller);

        // Calculate optimal amount to borrow
        uint borrowAmount = calcBorrowAmount(orderedReserves);
       
        // Calculate two pools' amountIn and amountOut according to borrowAmount
        (uint baseTokenOutAmount, uint debtAmount, uint profitAmount) = calcBaseTokenOutAmount(orderedReserves, info, targetBPool, targetUniPool, borrowAmount);

        // Set flashloan callbackData
        bytes memory callbackData = setCallbackData(orderedReserves, info, debtAmount, baseTokenOutAmount, borrowAmount);
        
        // Excute balancer's flashloan
        uint balanceBefore = IERC20(info.baseToken).balanceOf(address(this));
        uint[] memory amounts = new uint[](1);
        amounts[0] = debtAmount;
        IERC20[] memory tokens = new IERC20[](1);
        tokens[0] = IERC20(info.baseToken);
        makeFlashLoan(tokens, amounts, callbackData);

        // Check final balance
        uint256 balanceAfter = IERC20(info.baseToken).balanceOf(address(this));
        require(balanceAfter > balanceBefore, 'Losing money');
        success = true;

        console2.log('Borrow from pool:', info.lowerPool);
        console2.log('Sell to pool:', info.higherPool);
        console2.log('spotUPrice:', info.spotUPrice);
        console2.log('spotBPrice:', info.spotBPrice);
        console2.log('profit:', profitAmount);
        console2.log('borrowAmount(quoteToken):', borrowAmount);
    }

    function makeFlashLoan(
        IERC20[] memory tokens,
        uint256[] memory amounts,
        bytes memory userData
    ) internal {
      vault.flashLoan(this, tokens, amounts, userData);
    }

    function receiveFlashLoan(
        IERC20[] memory tokens,
        uint256[] memory amounts,
        uint256[] memory feeAmounts,
        bytes memory userData
    ) external override {
        require(msg.sender == VAULT_ADDRESS);
        
        CallbackData memory info = abi.decode(userData, (CallbackData));

        if (info.spotUPrice > info.spotBPrice) {
            // First swap in BPool (lowPool)
            IERC20(info.debtToken).approve(info.debtPool, type(uint).max);
            (uint tokenAmountOut,) = IBPool(info.debtPool).swapExactAmountIn(info.debtToken, info.debtAmount, info.borrowedToken, 0, type(uint).max);
            
            // Second swap in UniPool (higherPool)
            IERC20(info.borrowedToken).approve(info.targetPool, type(uint).max);
            (uint256 amount0Out, uint256 amount1Out) =
                info.debtTokenSmaller ? (info.debtTokenOutAmount, uint256(0)) : (uint256(0), info.debtTokenOutAmount);
            IERC20(info.borrowedToken).transfer(info.targetPool, info.borrowAmount);
            IUniswapV2Pair(info.targetPool).swap(amount0Out, amount1Out, address(this), "");
            
            // Repay to vault
            IERC20(info.debtToken).transfer(VAULT_ADDRESS, info.debtAmount);
        } else {
            // First swap in UniPool (lowPool)
            IERC20(info.debtToken).approve(info.debtPool, type(uint).max);
            (uint256 amount0Out, uint256 amount1Out) =
                info.debtTokenSmaller ? (uint256(0), info.borrowAmount) : (info.borrowAmount, uint256(0));
            IERC20(info.debtToken).transfer(info.debtPool, info.debtAmount);
            IUniswapV2Pair(info.debtPool).swap(amount0Out, amount1Out, address(this), "");
            
            // Second swap in BPool (higherPool)
            IERC20(info.borrowedToken).approve(info.targetPool, type(uint).max);
            (uint tokenAmountOut,) = IBPool(info.targetPool).swapExactAmountIn(info.borrowedToken, info.borrowAmount, info.debtToken, 0, type(uint).max);
            
            // Repay to vault
            IERC20(info.debtToken).transfer(VAULT_ADDRESS, info.debtAmount);
        }
    }

    function uniswapV2Call(
        address sender,
        uint256 amount0,
        uint256 amount1,
        bytes memory data
    ) public {
        CallbackData memory info = abi.decode(data, (CallbackData));

        // access control
        require(msg.sender == info.debtPool, 'Not from debtPool address call');
        require(sender == address(this), 'Not from this contract');

        // Swap quote token in unipool with higher price 
        uint256 borrowedAmount = amount0 > 0 ? amount0 : amount1;
        IERC20(info.borrowedToken).transfer(info.targetPool, borrowedAmount);
        (uint256 amount0Out, uint256 amount1Out) =
            info.debtTokenSmaller ? (info.debtTokenOutAmount, uint256(0)) : (uint256(0), info.debtTokenOutAmount);
        IUniswapV2Pair(info.targetPool).swap(amount0Out, amount1Out, address(this), new bytes(0));

        // Pay back to flashswap
        IERC20(info.debtToken).transfer(info.debtPool, info.debtAmount);
    }

    function excuteArbitrageWithinUniPools(
        address pool0, 
        address pool1
    ) 
        external 
        returns (
            bool success
        )
    {
        // Check if base token smaller than quote token
        SamePoolInfo memory info;
        (info.baseTokenSmaller, info.baseToken, info.quoteToken) = isbaseTokenSmaller(pool0, pool1);
        
        // Get two pools reserves in order
        OrderedReserves memory orderedReserves;
        (info.lowerPool, info.higherPool, info.price0, info.price1, orderedReserves) = getOrderedReserves(pool0, pool1, info.baseTokenSmaller);

        uint256 balanceBefore = IERC20(info.baseToken).balanceOf(address(this));

        // avoid stack too deep error
        {
            // Calculate optimal amount to borrow
            uint256 borrowAmount = calcBorrowAmount(orderedReserves);
            (uint256 amount0Out, uint256 amount1Out) =
                info.baseTokenSmaller ? (uint256(0), borrowAmount) : (borrowAmount, uint256(0));
            // borrow quote token on lower price pool, calculate how much debt we need to pay demoninated in base token
            uint256 debtAmount = getAmountIn(borrowAmount, orderedReserves.a1, orderedReserves.b1);
            // sell borrowed quote token on higher price pool, calculate how much base token we can get
            uint256 baseTokenOutAmount = getAmountOut(borrowAmount, orderedReserves.b2, orderedReserves.a2);
            require(baseTokenOutAmount > debtAmount, 'Arbitrage fail, no profit (within two UniPools)');
            console2.log('Profit (within two UniPools):', (baseTokenOutAmount - debtAmount));

            // can only initialize this way to avoid stack too deep error
            CallbackData memory callbackData;
            callbackData.debtPool = info.lowerPool;
            callbackData.targetPool = info.higherPool;
            callbackData.debtTokenSmaller = info.baseTokenSmaller;
            callbackData.borrowedToken = info.quoteToken;
            callbackData.debtToken = info.baseToken;
            callbackData.debtAmount = debtAmount;
            callbackData.debtTokenOutAmount = baseTokenOutAmount;

            bytes memory data = abi.encode(callbackData);
            IUniswapV2Pair(info.lowerPool).swap(amount0Out, amount1Out, address(this), data);
        }

        uint256 balanceAfter = IERC20(info.baseToken).balanceOf(address(this));
        require(balanceAfter > balanceBefore, 'Losing money');
        success = true;

        console2.log('Borrow from pool:', info.lowerPool);
        console2.log('Sell to pool:', info.higherPool);
        console2.log('profit:', balanceAfter - balanceBefore);
    }
    
    function getProfit(address pool0, address pool1) external view returns (uint256 profit, address baseToken) {
        (bool baseTokenSmaller, , ) = isbaseTokenSmaller(pool0, pool1);
        baseToken = baseTokenSmaller ? IUniswapV2Pair(pool0).token0() : IUniswapV2Pair(pool0).token1();

        (, , , , OrderedReserves memory orderedReserves) = getOrderedReserves(pool0, pool1, baseTokenSmaller);

        uint256 borrowAmount = calcBorrowAmount(orderedReserves);
        // borrow quote token on lower price pool,
        uint256 debtAmount = getAmountIn(borrowAmount, orderedReserves.a1, orderedReserves.b1);
        // sell borrowed quote token on higher price pool
        uint256 baseTokenOutAmount = getAmountOut(borrowAmount, orderedReserves.b2, orderedReserves.a2);
        if (baseTokenOutAmount < debtAmount) {
            profit = 0;
        } else {
            profit = baseTokenOutAmount - debtAmount;
        }
    }

    function calcBorrowAmount(OrderedReserves memory reserves) internal pure returns (uint256 amount) {
        // we can't use a1,b1,a2,b2 directly, because it will result overflow/underflow on the intermediate result
        // so we:
        //    1. divide all the numbers by d to prevent from overflow/underflow
        //    2. calculate the result by using above numbers
        //    3. multiply d with the result to get the final result
        // Note: this workaround is only suitable for ERC20 token with 18 decimals, which I believe most tokens do

        uint256 min1 = reserves.a1 < reserves.b1 ? reserves.a1 : reserves.b1;
        uint256 min2 = reserves.a2 < reserves.b2 ? reserves.a2 : reserves.b2;
        uint256 min = min1 < min2 ? min1 : min2;

        // choose appropriate number to divide based on the minimum number
        uint256 d;
        if (min > 1e24) {
            d = 1e20;
        } else if (min > 1e23) {
            d = 1e19;
        } else if (min > 1e22) {
            d = 1e18;
        } else if (min > 1e21) {
            d = 1e17;
        } else if (min > 1e20) {
            d = 1e16;
        } else if (min > 1e19) {
            d = 1e15;
        } else if (min > 1e18) {
            d = 1e14;
        } else if (min > 1e17) {
            d = 1e13;
        } else if (min > 1e16) {
            d = 1e12;
        } else if (min > 1e15) {
            d = 1e11;
        } else {
            d = 1e10;
        }

        (int256 a1, int256 a2, int256 b1, int256 b2) =
            (int256(reserves.a1 / d), int256(reserves.a2 / d), int256(reserves.b1 / d), int256(reserves.b2 / d));

        int256 a = a1 * b1 - a2 * b2;
        int256 b = 2 * b1 * b2 * (a1 + a2);
        int256 c = b1 * b2 * (a1 * b2 - a2 * b1);

        (int256 x1, int256 x2) = calcSolutionForQuadratic(a, b, c);

        // 0 < x < b1 and 0 < x < b2
        require((x1 > 0 && x1 < b1 && x1 < b2) || (x2 > 0 && x2 < b1 && x2 < b2), 'Wrong input order');
        amount = (x1 > 0 && x1 < b1 && x1 < b2) ? uint256(x1) * d : uint256(x2) * d;
    }
    
    // copy from amm-arbitrageur
    function calcSolutionForQuadratic(
        int256 a,
        int256 b,
        int256 c
    ) internal pure returns (int256 x1, int256 x2) {
        // find solution of quadratic equation: ax^2 + bx + c = 0, only return the positive solution
        int256 m = b**2 - 4 * a * c;
        // m < 0 leads to complex number
        require(m > 0, 'Complex number');

        int256 sqrtM = int256(sqrt(uint256(m)));
        x1 = (-b + sqrtM) / (2 * a);
        x2 = (-b - sqrtM) / (2 * a);
    }

    // copy from amm-arbitrageur
    function sqrt(uint256 n) internal pure returns (uint256 res) {
        assert(n > 1);

        // Newton’s method for caculating square root of n
        // The scale factor is a crude way to turn everything into integer calcs.
        // Actually do (n * 10 ^ 4) ^ (1/2)
        uint256 _n = n * 10**6;
        uint256 c = _n;
        res = _n;

        uint256 xi;
        while (true) {
            xi = (res + c / res) / 2;
            // don't need be too precise to save gas
            if (res - xi < 1000) {
                break;
            }
            res = xi;
        }
        res = res / 10**3;
    }

    // copy from UniswapV2Library
    function getAmountIn(
        uint256 amountOut,
        uint256 reserveIn,
        uint256 reserveOut
    ) internal pure returns (uint256 amountIn) {
        require(amountOut > 0, 'UniswapV2Library: INSUFFICIENT_OUTPUT_AMOUNT');
        require(reserveIn > 0 && reserveOut > 0, 'UniswapV2Library: INSUFFICIENT_LIQUIDITY');
        uint256 numerator = reserveIn * (amountOut) * (1000);
        uint256 denominator = (reserveOut - amountOut) * (997);
        amountIn = (numerator / denominator) + (1);
    }

    // copy from UniswapV2Library
    function getAmountOut(
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut
    ) internal pure returns (uint256 amountOut) {
        require(amountIn > 0, 'UniswapV2Library: INSUFFICIENT_INPUT_AMOUNT');
        require(reserveIn > 0 && reserveOut > 0, 'UniswapV2Library: INSUFFICIENT_LIQUIDITY');
        uint256 amountInWithFee = amountIn * (997);
        uint256 numerator = amountInWithFee * (reserveOut);
        uint256 denominator = (reserveIn * (1000)) + (amountInWithFee);
        amountOut = numerator / denominator;
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
        internal pure
        returns (uint spotPrice)
    {
        uint numer = bdiv(tokenBalanceIn, tokenWeightIn);
        uint denom = bdiv(tokenBalanceOut, tokenWeightOut);
        uint ratio = bdiv(numer, denom);
        uint scale = bdiv(BONE, bsub(BONE, swapFee));
        return  (spotPrice = bmul(ratio, scale));
    }
}