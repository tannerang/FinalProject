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

## 測試報告

| File             | % Lines          | % Statements     | % Branches     | % Funcs         |
|------------------|------------------|------------------|----------------|-----------------|
| src/FlashBot.sol | 88.16% (216/245) | 90.45% (284/314) | 48.94% (46/94) | 100.00% (28/28) |
| Total            | 88.16% (216/245) | 90.45% (284/314) | 48.94% (46/94) | 100.00% (28/28) |

## 數學計算

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


**Balancer: Spot Price Calc**

<img width="124" alt="image" src="https://github.com/tannerang/FinalProject/assets/57789692/80447c0b-cad2-4851-846d-612f9e23aa1e">

**Balancer: Out-Given-In**

<img width="253" alt="image" src="https://github.com/tannerang/FinalProject/assets/57789692/7abf0153-c470-4662-92a7-b38889a8b54d">

**Balancer: In-Given-Out**

<img width="257" alt="image" src="https://github.com/tannerang/FinalProject/assets/57789692/7400c51f-14e1-409e-b722-9a9051cb3297">

