pragma solidity >=0.5.0;

interface IBPool {
    function getBalance(address token) external view returns (uint);
    function getSpotPrice(address tokenIn, address tokenOut) external view returns (uint spotPrice);
    function getSwapFee() external view returns (uint);
    function getDenormalizedWeight(address token) external view returns (uint);
    function getNormalizedWeight(address token) external view returns (uint);
    function calcOutGivenIn(uint tokenBalanceIn, uint tokenWeightIn, uint tokenBalanceOut, uint tokenWeightOut, uint tokenAmountIn, uint swapFee) external pure returns (uint tokenAmountOut);
    function calcInGivenOut( uint tokenBalanceIn, uint tokenWeightIn, uint tokenBalanceOut, uint tokenWeightOut, uint tokenAmountOut, uint swapFee) external pure returns (uint tokenAmountIn);
    function swapExactAmountIn(address tokenIn, uint tokenAmountIn, address tokenOut, uint minAmountOut, uint maxPrice) external returns (uint tokenAmountOut, uint spotPriceAfter);
    function swapExactAmountOut(address tokenIn, uint maxAmountIn, address tokenOut, uint tokenAmountOut, uint maxPrice) external returns (uint tokenAmountIn, uint spotPriceAfter);
}
