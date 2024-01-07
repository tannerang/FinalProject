//const { abi: SwapRouterAbi} = require('@uniswap/v3-periphery/artifacts/contracts/SwapRouter.sol/SwapRouter.json')
const ethers = require("ethers");
const v2PairAbi = require('./abi/IUniswapV2Pair.json');

//const contractInterface = new ethers.utils.Interface(SwapRouterAbi);
const contractInterface = new ethers.Interface(v2PairAbi);


require('dotenv').config()
//const provider = new ethers.providers.WebSocketProvider(process.env.WEBSOCKET_URL)
const provider = new ethers.WebSocketProvider(process.env.WEBSOCKET_URL)

const main = async () => {
    provider.on('pending', async (hash) => {
        getTransaction(hash)
    });
};

const delay = (ms) => new Promise(resolve => setTimeout(resolve, ms))
const UNISWAP_ADDRESSES = [
    '0xE592427A0AEce92De3Edee1F18E0157C05861564', // swap router
]

const BAL_WETH_V2 = '0xA70d458A4d9Bc0e6571565faee18a48dA5c0D593' // BAL / WETH
const USDT_WETH_V2 = '0x0d4a11d5eeaac28ec3f61d100daf4d40471f1852' // USDT / WETH

const USDT_ADDRESSES = [
    '0xdAC17F958D2ee523a2206206994597C13D831ec7',
]


const v2Pair = new ethers.Contract(BAL_WETH_V2, v2PairAbi, provider)


let txIdx = 0
const getTransaction = async (transactionHash) => {
    for (let attempt = 1; attempt <= 2; attempt++) {
        const tx = await provider.getTransaction(transactionHash);
        if (tx) {
            if (USDT_ADDRESSES.includes(tx.to)) {
                txIdx += 1
                const data = tx.data
                console.log('==============================', `Tx: ${txIdx}`, '==============================')
                console.log(tx)
                //decodeTransaction(data, txIdx)
                await delay(10000);

                break
            }
        }
        await delay(10000);
    }
}

main()

/*
    node bot/ListenPendingTx.js
*/