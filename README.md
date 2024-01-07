## 專案簡介
- 合約支援 UniswapV2 之間與 Balancer BPool 和 UniswapV2 之間的 AMM 套利。
- 鑑於目前 Balancer flashloan 處於 0% 交易手續費狀態，以及 Balancer BPool (0.001% - 10%) 容易擁有相較 UniswapV2 Pool (0.3%) 更低的交易手續費，故選擇支援 Balancer AMM，可選擇的池子可參考此[連結](<https://pools.balancer.exchange/#/explore>)


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

<img width="943" alt="image" src="https://github.com/tannerang/FinalProject/assets/57789692/ccbfe916-1419-4c66-ba98-e16105cc95c5">


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

|                 | Pair0 | Pair1 |
| :---------------| :---- | :---- |
| Base Token 餘額  | a1    |   a2  |
| Quote Token 餘額 | b1    |   b2  |

**Balancer: Spot Price Calc**

<img width="124" alt="image" src="https://github.com/tannerang/FinalProject/assets/57789692/80447c0b-cad2-4851-846d-612f9e23aa1e">

**Balancer: Out-Given-In**

<img width="253" alt="image" src="https://github.com/tannerang/FinalProject/assets/57789692/7abf0153-c470-4662-92a7-b38889a8b54d">

**Balancer: In-Given-Out**

<img width="257" alt="image" src="https://github.com/tannerang/FinalProject/assets/57789692/7400c51f-14e1-409e-b722-9a9051cb3297">

