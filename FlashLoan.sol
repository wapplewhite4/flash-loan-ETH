pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import { FlashLoanReceiverBase } from "./FlashLoanReceiverBase.sol";
import { ILendingPool, ILendingPoolAddressesProvider, IERC20 } from "./Interfaces.sol";
import {SafeMath} from "./Libraries.sol";
import "./Ownable.sol";
import "@chainlink/contracts/src/v0.6/interfaces/AggregatorV3Interface.sol";


contract FlashLoan is FlashLoanReceiverBase, Ownable {
   
  
  ILendingPool public lendingPool;
  

  AggregatorV3Interface internal priceFeedKucoin;
  AggregatorV3Interface internal priceFeedCoinbase;

  address public coinbase;
  address public kucoin;

  mapping (bytes32 => uint256) public priceMap;

  constructor(address _coinbase, address _kucoin, address _aave) public {
    lendingPool = ILendingPool(ILendingPoolAddressesProvider(_aave).getLendingPool());
    coinbase = _coinbase;
    kucoin = _kucoin;
    owner = msg.sender;
    priceFeedKucoin = AggregatorV3Interface(0x3E7d1eAB13ad0104d2750B8863b489D65364e32D);
    priceFeedCoinbase = AggregatorV3Interface(0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6);
    aave = IAave(_aave);
}
 function arbitrage(address coinbase, address kucoin, uint256 flashLoanAmount, uint256 minimumProfit ) public onlyOwner{
    uint256 coinbasePrice = getPrice(coinbase);
    uint256 kucoinPrice = getPrice(kucoin);
    uint256 profit = coinbasePrice - kucoinPrice;

    if (profit < minimumProfit) {
      // Abort if the profit is below the minimum threshold
      return;
    }

    // Flash loan from Aave
    uint256 flashLoanId = aave.flashLoan(flashLoanAmount);

    if (flashLoanId == 0) {
    // Flash loan has not been approved, abort
    return;
  }
    // Buy from Coinbase
    buyFromExchange(coinbase, flashLoanAmount / coinbasePrice);

    // Sell on KuCoin
    sellOnExchange(kucoin, flashLoanAmount / kucoinPrice);

    // Repay the flash loan
    aave.flashLoanRepay(flashLoanId);
  }

  function getLatestPrice(address exchange) public view returns (uint256) {
        if (exchange == 0xaD6D458402F60fD3Bd25163575031ACDce07538D) { // Kucoin ETH/USDT price feed address
            (, int256 price, , , ) = priceFeedKucoin.latestRoundData();
            return uint256(price);
        } else if (exchange == 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419) { // Coinbase ETH/USD price feed address
            (, int256 price, , , ) = priceFeedCoinbase.latestRoundData();
            return uint256(price);
        } else {
            revert("Unsupported exchange");
        }
    }

  function __callback(bytes32 myid, string memory result) public {
    if (msg.sender != oraclize_cbAddress()) revert();

    uint256 price = parsePrice(result);
    priceMap[myid] = price;
  }

  function parsePrice(string memory response) public view returns (uint256) {
    // Initialize a variable to store the token price
    uint256 price;

    // Try to parse the response string to a JSON object
    
        JsonObject memory json = JSON.parse(response).asObject();

        // Extract the price from the JSON object
        price = json["data"][0]["price"].asString().toUint();
    

    // Return the price
    return price;
}
function buyFromExchange(address exchange, uint256 amount) public {
  // Send a transaction to the exchange's smart contract to purchase the specified amount of ETH
  // Check if the exchange is Coinbase
  if (exchange != coinbase) {
    revert("Invalid exchange");
  }

  // Call Coinbase's API to buy ETH for the specified amount
  bytes memory query = abi.encodePacked("POST", "/v2/orders", abi.encodePacked(
    "{\"size\": \"" + amount + "\", \"price\": \"" + priceMap[coinbase] + "\", \"side\": \"buy\", \"product_id\": \"ETH-USD\"}"
  ));
  bytes32 queryId = oraclize_query(60, "URL", "json", query);
}

function sellOnExchange(address exchange, uint256 amount) public {
  // Send a transaction to the exchange's smart contract to sell the specified amount of ETH
  // Check if the exchange is KuCoin
  if (exchange != kucoin) {
    revert("Invalid exchange");
  }

  // Query the KuCoin API to execute the trade
  bytes memory query = abi.encodePacked(
    "POST",
    "/v1/order",
    "symbol=ETH-USDT&type=SELL&price=" + priceMap[kucoin] + "&amount=" + amount
  );
  bytes32 queryId = oraclize_query(60, "URL", "json", query);

  // Update the priceMap with the trade details
  priceMap[queryId] = amount;
}

}


