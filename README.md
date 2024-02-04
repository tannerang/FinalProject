## 專案簡介
- 一個自動化套利機器人，在不同 DEX 之間利用 FlashLoan 進行套利活動
- 支援 UniswapV2 之間與 Balancer 和 UniswapV2 之間的 AMM 套利
- 使用 BalancerV2 FlashLoan 旨在利用目前 0% 手續費的特點將利潤最大化
- 因 Balancer 池 (0.001% - 10%) 比起 UniswapV2 池 (0.3%) 容易有更低的手續費，故合約支援 Balancer AMM，可選擇的池子請參考此[連結](<https://pools.balancer.exchange/#/explore>)
- Bot 負責監聽 AMM Swap Event 並觸發合約執行套利

## 合約架構

<img width="718" alt="image" src="https://github.com/tannerang/FinalProject/assets/57789692/3a8dbbbd-4a0f-4185-aeed-3010c3da989e">


## 流程說明
套利使用 Balancer 的 Flashloan 功能，套利流程為：
- 檢查同一交易對 (e.g. BAL/WETH) 在不同 AMM (Pair0 和 Pair1) 中是否存在價差
- 假設 Pair0 和 Pair1 之間存在差價，合約計算兩個 pair 中的 Quote Token 價格
- 令 Pair0 為 lowerPrice Pool，Pair1 為 higherPrice Pool
- 計算 Pair0 和 Pair1 中最佳的 borrowAmount (Quote Token Amount) 使套利收益最大化。
- 藉由 borrowAmount 推算出 Pair0 的 amountIn (Base Token) 與 Pair1 的 amountOut (Base Token)
- 執行 makeFlashLoan，透過 Balancer Flashloan 借出數量為 amountIn 的 Base Token，
- 在 receiveFlashLoan 中向 lowerPrice Pool 買入 amountIn 數量的 Base Token， 接著向 Pair1 中賣出 amountOut 數量的 Base Token，最後 repayFlashloan amountIn 數量的 Base Token
- (amountOut - amountIn) 的 Base Token 即為本次交易淨利

<img width="895" alt="image" src="https://github.com/tannerang/FinalProject/assets/57789692/5ba262c8-d374-46c6-af96-1ac618a974a7">

## 執行說明
```
$ git clone https://github.com/tannerang/FinalProject.git
$ cd FinalProject
$ forge install
$ forge test
```
```
// in .env file
MAINNET_RPC_URL=https://eth-mainnet.g.alchemy.com/v2/<YOUR_RPC_URL>
INFURA_WEBSOCKET_URL=wss://mainnet.infura.io/ws/v3/<YOUR_API_KEY>
```

## 測試報告

| File             | % Lines          | % Statements     | % Branches     | % Funcs         |
|------------------|------------------|------------------|----------------|-----------------|
| src/FlashBot.sol | 88.16% (216/245) | 90.45% (284/314) | 48.94% (46/94) | 100.00% (28/28) |
| Total            | 88.16% (216/245) | 90.45% (284/314) | 48.94% (46/94) | 100.00% (28/28) |

## 注意事項
- 目前僅包含 UniSwapV2、Balancer 兩種 AMM
- 目前僅適用 `Decimal = 1e18` 的代幣
- Balancer AMM 適用的池子僅限於代幣權重皆為 50%
- Base Token 預設為 WETH

## 數學推導

已知 `Pair0 = Lower Price Pool`、`Pair1 = Higher Price Pool`，假設 Pair0 與 Pair1 的初始狀態如下：

|                     | Pair0 | Pair1 |
| :-------------------| :---- | :---- |
| Base Token Reserve  | a1    |   a2  |
| Quote Token Reserve | b1    |   b2  |


我們預計在較便宜的 Pair0 中買入 `Delta b1` 數量的 Quote Token，基於 `x * y = k` 的公式，可得：

![image](https://github.com/tannerang/FinalProject/assets/57789692/eb44137d-a9d4-44c7-94f0-ca0bfad6a266)

接著在較高價的 Pair1 中賣出 `Delta b2` 數量的 Quote Token，可得：

![image](https://github.com/tannerang/FinalProject/assets/57789692/f6ab43cf-5474-4166-a665-1e59cdd353cb)

整理上方兩式得：

![image](https://github.com/tannerang/FinalProject/assets/57789692/8154fdee-0303-4663-a32b-9f86f44ade88)

因我們在低價池買入的 Quote Token 數量和在高價池賣出的 Quote Token 數量相同，故 `Delta b1 = Delta b2 (= Delta b)`

我們令 `x = Delta b`，那麼 x 與利潤 (`Delta a2 - Delta a1`) 的函數為：

![image](https://github.com/tannerang/FinalProject/assets/57789692/13052514-14be-4fb7-b6db-49e606556d7b)

欲求出利潤最大時的 x 值，可以對上面的函數求導函數：

![image](https://github.com/tannerang/FinalProject/assets/57789692/bce0160f-fc86-41cf-969c-ab47998a1019)

當導函數為 0 時，存在極大/極小值，再透過一些條件設定忽略極小值時的解。令導函數等於 0 得：

![image](https://github.com/tannerang/FinalProject/assets/57789692/cdddad12-01d7-4880-837a-1a377c34cdf3)

![image](https://github.com/tannerang/FinalProject/assets/57789692/e538ad3e-727f-46d2-ba30-6da2fa4f2676)

我們假設：

![image](https://github.com/tannerang/FinalProject/assets/57789692/f11276d8-a67a-426b-8ed6-d40ab7a8a68e)

將前述的方程式轉換成一般的一元二次方程式：

![image](https://github.com/tannerang/FinalProject/assets/57789692/a0c07f4c-be6f-40c7-baf5-d6c3173a2c96)

得解：

![image](https://github.com/tannerang/FinalProject/assets/57789692/08b2861e-efe4-4df1-bc56-6a84d1f555ed)

最後求出滿足條件的 x 值，即為能使利潤最大化的 Quote Token 數量

## 進階計算

然而，上述推論僅適用於符合 `x * y = k` 公式的 AMM，也就是交易對僅包含兩種代幣且權重各為 50% 的 AMM
無法適用像 Balancer 這種可以自定義交易對代幣數量和代幣權重的 AMM，這種 AMM 在利潤最大化之下的 Quote Token 最佳數量計算也隨之複雜

根據 [Balancer 白皮書](<https://balancer.fi/whitepaper.pdf>)，已知以下公式：

**Balancer: Spot Price Calc**

<img width="124" alt="image" src="https://github.com/tannerang/FinalProject/assets/57789692/80447c0b-cad2-4851-846d-612f9e23aa1e">

**Balancer: Out-Given-In**

<img width="253" alt="image" src="https://github.com/tannerang/FinalProject/assets/57789692/7abf0153-c470-4662-92a7-b38889a8b54d">

**Balancer: In-Given-Out**

<img width="257" alt="image" src="https://github.com/tannerang/FinalProject/assets/57789692/7400c51f-14e1-409e-b722-9a9051cb3297">

若我們想在符合 `x * y = k` 公式的 AMM 和 Balancer AMM 之間進行套利，假設 `PairB = Lower Price Pool` 和 `PairU = Higher Price Pool`，則初始狀態如下：(在此先不討論 `PairB = Higher Price Pool` 和 `PairU = Lower Price Pool` 的情況)

|                     | PairB | PairU |
| :-------------------| :---- | :---- |
| Base Token Reserve  | a1    |   a2  |
| Quote Token Reserve | b1    |   b2  |

因我們在低價池買入的 Quote Token 數量和在高價池賣出的 Quote Token 數量相同，故令 `Quote Token Amount = x`，則 x 與利潤的函數為：

![image](https://github.com/tannerang/FinalProject/assets/57789692/02b5ba2d-0d9e-4d9f-89b5-fac9008399ef)

其中：

![image](https://github.com/tannerang/FinalProject/assets/57789692/de0dcc87-b01c-4159-afdc-3d5a904efcf7)

![image](https://github.com/tannerang/FinalProject/assets/57789692/d4211137-f813-4cba-885f-a7691b86cf96)

為了避免 Token Weight 在指數讓導函數的表達式過於複雜，我們令：

![image](https://github.com/tannerang/FinalProject/assets/57789692/323c71ab-30f6-4fb0-a850-6ecf138065f8)

![image](https://github.com/tannerang/FinalProject/assets/57789692/ee9a1c29-6239-4831-a5c5-2dd4f6fd2682)

再令：

![image](https://github.com/tannerang/FinalProject/assets/57789692/c12f6056-5d89-4a46-ad87-04895b64f697)

![image](https://github.com/tannerang/FinalProject/assets/57789692/d3a3947a-2146-4cc8-92ee-852394a95cc7)

同樣地，欲求出利潤最大時的 x 值，對上面的函數求導函數，得下：

![image](https://github.com/tannerang/FinalProject/assets/57789692/7363b1e0-6cc5-4ef9-91c0-471e02a28452)

由於當 k 為浮點數時會大幅增加計算難度，故排除考慮所有情況下的權重，僅以實務上常見的權重為主

一般來說，在任意 Balancer AMM 當中的任兩個 Token Weight 幾乎都會落在 20% ~ 80% 的比例之中，也就是 k 值高機率會落在 4 ~ 0.25 之間

此時假設 k 為整數，得：

![image](https://github.com/tannerang/FinalProject/assets/57789692/90e4e85a-6144-4247-9bcf-58601c95b441)

當 `k = 1` 時：

<img width="446" alt="image" src="https://github.com/tannerang/FinalProject/assets/57789692/60475e1f-5d02-4853-81fd-31fb6b3dab9c">

分別將 `a, b, c, d = a1, b1, a2, b2` 代回公式，整理後可得一元二次方程式：

![image](https://github.com/tannerang/FinalProject/assets/57789692/e538ad3e-727f-46d2-ba30-6da2fa4f2676)

剩下步驟如數學推導後半段，此不贅述

---------------------------------------------------------------------------------------------------

最後可以發現，當 `k = 1` 的時候，代表兩代幣權重一致 `Wb/Wa = 1`，也與 `x * y = k` AMM 的計算過程一模一樣，故進行套利時適用代幣權重皆為 50% 的 Balancer AMM。惟 `k = 2, 3, 4` 時，公式化簡後會變成一元三次、一元四次、一元五次方程式，無法直接帶入公式解求根，故合約不支援其他 k 值的運算

**以上說明了注意事項第三點 Balancer AMM 僅適用代幣權重皆為 50% 的池子原因**
