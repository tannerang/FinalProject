//const { abi: SwapRouterAbi} = require('@uniswap/v3-periphery/artifacts/contracts/SwapRouter.sol/SwapRouter.json')
const ethers = require("ethers");
const v2PairAbi = require('./abi/IUniswapV2Pair.json');

//const contractInterface = new ethers.utils.Interface(SwapRouterAbi);
const contractInterface = new ethers.Interface(v2PairAbi);


require('dotenv').config()
//const provider = new ethers.providers.WebSocketProvider(process.env.WEBSOCKET_URL)

// INFURA_WEBSOCKET_URL
const provider = new ethers.WebSocketProvider(process.env.INFURA_WEBSOCKET_URL)
// ALCHEMY_WEBSOCKET_URL
// const provider = new ethers.WebSocketProvider(process.env.ALCHEMY_WEBSOCKET_URL)
const delay = (ms) => new Promise(resolve => setTimeout(resolve, ms))

const main = async () => {
    provider.on('pending', async (hash) => {
        getTransaction(hash)
    });
};

const UNISWAP_ADDRESSES = [
    '0xE592427A0AEce92De3Edee1F18E0157C05861564', // swap router
]

const BAL_WETH_V2 = '0xA70d458A4d9Bc0e6571565faee18a48dA5c0D593' // BAL / WETH
const USDT_WETH_V2 = '0x0d4a11d5eeaac28ec3f61d100daf4d40471f1852' // USDT / WETH
/*
const USDT_ADDRESSES = [
    '0xdAC17F958D2ee523a2206206994597C13D831ec7',
]
*/

const v2Pair = new ethers.Contract(BAL_WETH_V2, v2PairAbi, provider)


let txIdx = 0
const getTransaction = async (transactionHash) => {
    //for (let attempt = 1; attempt <= 2; attempt++) {
        await delay(3000);
        const tx = await provider.getTransaction(transactionHash);
        if (tx) {
            if (USDT_WETH_V2.includes(tx.to)) {
                txIdx += 1
                const data = tx.data
                console.log('==============================', `Tx: ${txIdx}`, '==============================')
                console.log(tx)
                decodeTransaction(data, txIdx)
                //break
            }
        }
        await delay(3000);
    //}
}

const decodeTransaction = (txInput, txIdx, isMulticall = false) => {
    const decodedData = contractInterface.parseTransaction({ data: txInput })

    const functionName = decodedData.name

    const args = decodedData.args
    const params = args.params
    const data = args.data

    logFunctionName(functionName, txIdx, isMulticall)

    if (functionName === 'swap') { return logSwap(params) }

    if (functionName === 'exactInputSingle') { return logExactInputSingle(params) }

    if (functionName === 'exactOutputSingle') { return logExactOutputSingle(params) }

    if (functionName === 'exactInput') { return logExactInput(params) }

    if (functionName === 'exactOutput') { return logExactOutput(params) }

    if (functionName === 'selfPermit') { return logSelfPermit(args) }

    if (functionName === 'refundETH') { return logRefundETH(args) }

    if (functionName === 'unwrapWETH9') { return logUnwrapWETH9(args) }

    if (functionName === 'multicall') { return parseMulticall(data, txIdx) }

    console.log('ADD THIS FUNCTION:', functionName)
    console.log('decodedData:', decodedData)
}

const logFunctionName = (functionName, txIdx, isMulticall) => {
    if (isMulticall) {
        console.log()
        console.log('-------', `Fn: ${txIdx}`, functionName);
        return
    }

    console.log()
    console.log('======================================================================================')
    console.log('==============================', `Tx: ${txIdx} - ${functionName}`, '==============================')
    console.log('======================================================================================')
}

const parseMulticall = (data, txIdx) => {
    data.forEach((tx, fnIdx) => {
        decodeTransaction(tx, fnIdx, true)
    })
}

const logSwap = (params) => {
    console.log('amount0Out:       ', params.amount0Out)
    console.log('amount1Out:       ', params.amount1Out)
    console.log('to:               ', params.to)
    console.log('data:             ', params.data)
}

const logUnwrapWETH9 = (args) => {
    console.log('amountMinimum:    ', args.amountMinimum)
    console.log('recipient:        ', args.recipient)
}

const logExactInputSingle = (params) => {
    console.log('tokenIn:          ', params.tokenIn)
    console.log('tokenOut:         ', params.tokenOut)
    console.log('fee:              ', params.fee)
    console.log('recipient:        ', params.recipient)
    console.log('deadline:         ', params.deadline)
    console.log('amountIn:         ', params.amountIn)
    console.log('amountOutMinimum: ', params.amountOutMinimum)
    console.log('sqrtPriceLimitX96:', params.sqrtPriceLimitX96)
}

const logExactOutputSingle = (params) => {
    console.log('tokenIn:          ', params.tokenIn)
    console.log('tokenOut:         ', params.tokenOut)
    console.log('fee:              ', params.fee)
    console.log('recipient:        ', params.recipient)
    console.log('deadline:         ', params.deadline)
    console.log('amountOut:        ', params.amountOut)
    console.log('amountInMaximum:  ', params.amountInMaximum)
    console.log('sqrtPriceLimitX96:', params.sqrtPriceLimitX96)
}

const logExactInput = (params) => {
    console.log('path:             ', params.path)
    console.log('recipient:        ', params.recipient)
    console.log('deadline:         ', params.deadline)
    console.log('amountIn:         ', params.amountIn)
    console.log('amountOutMinimum: ', params.amountOutMinimum)
}

const logExactOutput = (params) => {
    console.log('path:             ', params.path)
    console.log('recipient:        ', params.recipient)
    console.log('deadline:         ', params.deadline)
    console.log('amountOut:        ', params.amountOut)
    console.log('amountInMaximum:  ', params.amountInMaximum)
}

const logSelfPermit = (params) => {
    console.log('token:            ', params.token)
    console.log('value:            ', params.value)
    console.log('deadline:         ', params.deadline)
}

const logRefundETH = (params) => {
    console.log('Nothing to log')
}


main()

/*
    node bot/ListenSwapEvent.js
*/