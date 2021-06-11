/*
    1.1.7
*/
// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;

import "../interfaces/AggregatorV3Interface.sol";
import "../libraries/Ownable.sol";
import "../interfaces/IOracle.sol";
import "../interfaces/IUniswapV2Pair.sol";
import "../libraries/UniswapV2OracleLibrary.sol";
import "../libraries/SafeERC20.sol";

/**
 * @title Oracle - the oracle contract for Spark
 * @author Sperax Dev Team
 * @notice this contract gets data from UniswapV2 pair and feed these data into the main contact of Spark, i.e. Spark.sol
 * @dev this contract draws insights from "ExampleOracleSimple.sol" by UniswapV2 team
 */

contract Oracle is IOracle, Ownable {
    using SafeMath for *;

    event Update(uint currPriceMA, uint currPricetime);

    struct token0Pricetime {
       uint32 timestamp;
       uint price0Cumulative;
    }

    //
    // Constants & Immutables
    //
    uint8 public constant FREQUENCY = 24;
    IUniswapV2Pair private immutable _pair;

    //
    // Core State Variables
    //
    // the moving average price of token0 denominated in token1
    // frequency = 24, default period = 1 hours ==> default timespan is 1 days
    uint public override token0PriceMA;

    //
    // Auxilliary State Variables
    //
    // the per-period cumulative pricetimes, i.e. the UniswapV2 price*time values, of token0
    token0Pricetime[FREQUENCY+1] public token0Pricetimes;
    uint32 public pricetimeOldestIndex;
    // the timstamp of the lastest price update
    uint32 public override lastUpdateTime;
    // the default period of one price update is 1 hours
    uint32 public override period = 1 hours;
	AggregatorV3Interface priceFeedETH;
	AggregatorV3Interface priceFeedUSDC;

	address public USDCAddr = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;



    //
    // Constructor
    //
    constructor(address pair_) public {
		priceFeedETH = AggregatorV3Interface(0x9326BFA02ADD2366b30bacB125260Af641031331);
        priceFeedUSDC = AggregatorV3Interface(0x9211c6b3BF41A10F78539810Cf5c64e1BB78Ec60);
        uint32 constructTime = uint32(now % 2 ** 32);
        _pair = IUniswapV2Pair(pair_);
        lastUpdateTime = constructTime;

        // obtain the cumulative pricetime from uniswapv2 pair deployment to now
        (uint pricetimeCorrection, , ) = UniswapV2OracleLibrary.currentCumulativePrices(pair_);

        // set up initial conditions
        // assume that 1 ETH = 2500 USD, 1 SPA = 0.02 USD, so 1 ETH = 125,000 SPA
        uint iniToken0Price = 125000;
        uint resolution = 112;
        uint unitPricetime = (iniToken0Price << resolution) * period;
        uint basePricetime = unitPricetime * FREQUENCY;

        // simulate the pricetimes of the past 7 days, including necessary correction
        token0PriceMA = iniToken0Price << resolution;
        for (uint i = 0; i < (FREQUENCY+1); i++) {
            token0Pricetimes[i].price0Cumulative = unitPricetime
                                                   .mul(i)
                                                   .add(pricetimeCorrection)
                                                   .sub(basePricetime);
            token0Pricetimes[i].timestamp = constructTime - period * uint32(FREQUENCY - i);
        }
    }

    //
    // Getter Function
    //
    /**
     * @notice get the address of the token pair pool
     * @return the pair pool address
     */
    function getPairAddr() external view returns (address) {
        return address(_pair);
    }

    //
    // Owner Only Function: changePeriod
    //

    /**
     * @notice change updating period
     * @dev the frequency of update always remains the same
     * @param newPeriod new minimal period in between two updates
     */
    function changePeriod(uint32 newPeriod) external onlyOwner {
        period = newPeriod;
    }


    //
    // Core Functions
    //

	function getETHPrice() public view returns (int) {
		(
			uint80 roundID,
			int price,
			uint startedAt,
			uint timeStamp,
			uint80 answeredInRound
		) = priceFeedETH.latestRoundData();
		return price;
	}
	function getUSDCPrice() public view returns (int) {
		(
			uint80 roundID,
			int price,
			uint startedAt,
			uint timeStamp,
			uint80 answeredInRound
		) = priceFeedUSDC.latestRoundData();
		return price;
	}
	function getSPAPrice() public view override returns (int) {
		int ETHPrice = getETHPrice();
		return int(token0PriceMA.mul(uint(ETHPrice)));
	}
	function price(address tokenAddr) public view override returns (int) {
		if (tokenAddr == USDCAddr) {
			return getUSDCPrice();
		}
	}

    /**
     * @notice update the price of token0 to the latest
     * @dev the price would be updated only once per period time
     */
    function update() external override {
        // check if enough time has elapsed for a new update
        uint32 currTime = uint32(now % 2 ** 32);
        uint32 timeElapsed = currTime - lastUpdateTime;
        require(timeElapsed >= period, "update() : the time elapsed is too short.");


        // query the lastest pricetime
        (uint price0Cumulative, , ) = UniswapV2OracleLibrary.currentCumulativePrices(address(_pair));

        // update the past-7-day pricetime array and record
        uint32 indexNew = pricetimeOldestIndex;
        uint32 indexOld = (indexNew + 1) % (FREQUENCY+1);
        token0Pricetimes[indexNew].price0Cumulative = price0Cumulative;
        token0Pricetimes[indexNew].timestamp = currTime;

        // calculate the new moving average price of token0
        uint timeElapsedMA =
            uint(token0Pricetimes[indexNew].timestamp - token0Pricetimes[indexOld].timestamp); // notice: overflow is preferred
        token0PriceMA = token0Pricetimes[indexNew].price0Cumulative
                         .sub(token0Pricetimes[indexOld].price0Cumulative)
                         .div(timeElapsedMA);

        // update global status
        lastUpdateTime = currTime;
        pricetimeOldestIndex = indexOld;
        emit Update(token0PriceMA, price0Cumulative);
    }
}
