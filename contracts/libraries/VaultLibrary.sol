// pragma solidity >=0.5.11;

// import "@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol";
// import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
// import "@openzeppelin/contracts-upgradeable/token/ERC20/SafeERC20Upgradeable.sol";
// import { BancorFormula } from "../libraries/BancorFormula.sol";
// import { IBasicToken } from "../interfaces/IBasicToken.sol";
// import "../interfaces/IOracle.sol";

// library VaultLibrary {
// 	using SafeERC20Upgradeable for ERC20Upgradeable;
// 	using SafeMathUpgradeable for uint;
    
// 	// note: chi_alpha_Prec = chiPrec
// 	/**
// 	 * @dev calculate chiTarget by the formula in section 2.2 of the whitepaper
// 	 * @param chiInit_ the initial value of chi
// 	 * @param blockPassed the number of blocks that have passed since USDs is launched, i.e. "Block Height"
// 	 * @param priceUSDs the price of USDs, i.e. "USDs Price"
// 	 * @param precisionUSDs the precision used in the variable "priceUSDs"
// 	 * @return chiTarget_ the value of chiTarget
// 	 */
// 	function chiTarget(
//         uint chiInit_, uint blockPassed, uint priceUSDs, uint precisionUSDs, uint chiPrec, uint chi_alpha, uint chi_alpha_Prec, uint chi_beta_Prec, uint chi_beta
//     ) public pure returns (uint chiTarget_) {
// 		uint chiAdjustmentA = blockPassed.mul(chiPrec).mul(chi_alpha).div(chi_alpha_Prec);
// 		uint chiAdjustmentB;
// 		uint afterB;
// 		if (priceUSDs >= precisionUSDs) {
// 			chiAdjustmentB = chi_beta.mul(chiPrec).mul(priceUSDs - precisionUSDs).mul(priceUSDs - precisionUSDs).div(chi_beta_Prec);
// 			afterB = chiInit_.add(chiAdjustmentB);
// 		} else {
// 			chiAdjustmentB = chi_beta.mul(chiPrec).mul(precisionUSDs - priceUSDs).mul(precisionUSDs - priceUSDs).div(chi_beta_Prec);
// 			(, afterB) = chiInit_.trySub(chiAdjustmentB);
// 		}
// 		(, chiTarget_) = afterB.trySub(chiAdjustmentA);
// 	}

// 	/**
// 	 * @dev calculate chiMint
// 	 * @return chiMint, i.e. chiTarget, since they share the same value 
// 	 */
// 	function chiMint(
//         address oracleAddr, uint startBlockHeight, uint chiInit, uint chiPrec, uint chi_alpha, uint chi_alpha_Prec, uint chi_beta_Prec, uint chi_beta
//     ) public returns (uint)  {
// 		uint priceUSDs = uint(IOracle(oracleAddr).getUSDsPrice());
// 		uint precisionUSDs = IOracle(oracleAddr).USDsPricePrecision();
// 		uint blockPassed = uint(block.number).sub(startBlockHeight);
// 		return chiTarget(chiInit, blockPassed, priceUSDs, precisionUSDs, chiPrec, chi_alpha, chi_alpha_Prec, chi_beta_Prec, chi_beta);
// 	}


// 	/**
// 	 * @dev calculate chiRedeem based on the formula at the end of section 2.2
// 	 * @return chiRedeem_
// 	 */
// 	function chiRedeem(
//         address oracleAddr, uint startBlockHeight, uint chiInit, uint chi_gamma, uint chi_gamma_Prec, uint collateralRatio_,
//         uint chiPrec, uint chi_alpha, uint chi_alpha_Prec, uint chi_beta_Prec, uint chi_beta
//     ) public returns (uint chiRedeem_) {
// 		// calculate chiTarget
// 		uint priceUSDs = uint(IOracle(oracleAddr).getUSDsPrice());
// 		uint precisionUSDs = IOracle(oracleAddr).USDsPricePrecision();
// 		uint blockPassed = uint(block.number).sub(startBlockHeight);
// 		uint chiTarget_ = chiTarget(chiInit, blockPassed, priceUSDs, precisionUSDs, chiPrec, chi_alpha, chi_alpha_Prec, chi_beta_Prec, chi_beta);
// 		// calculate chiRedeem
// 		if (chiTarget_ > collateralRatio_) {
// 			chiRedeem_ = chiTarget_.add(chi_gamma.mul(chiTarget_ - collateralRatio_).div(chi_gamma_Prec));
// 		} else {
// 			chiRedeem_ = chiTarget_;
// 		}
// 	}

// 	// Note: need to be less than (2^32 - 1)
// 	// Note: assuming when exponentWithPrec >= 2^32, toReturn >= swapFeePresion () (TO-DO: work out the number)
// 	/**
// 	 * @dev calculate the OutSwap fee, i.e. fees for redeeming USDs
// 	 * @return the OutSwap fee 
// 	 */
// 	function calculateSwapFeeOut(
//         bool swapfeeOutAllowed, uint swapFee_A, address oracleAddr, uint swapFee_A_Prec, uint swapFeePresion, uint swapFee_theta, uint swapFee_theta_Prec,
//         address BancorFormulaAddr_
//     ) public view returns (uint) {
// 		// if the OutSwap fee is diabled, return 0
// 		if (!swapfeeOutAllowed) {
// 			return 0;
// 		}

// 		// implement the formula in Section 4.3.2 of whitepaper
// 		uint USDsInOutRatio = IOracle(oracleAddr).USDsInOutRatio();
// 		uint USDsInOutRatioPrecision = IOracle(oracleAddr).USDsInOutRatioPrecision();
// 		if (USDsInOutRatio <= uint(12).mul(USDsInOutRatioPrecision).div(10)) {
// 			return swapFeePresion / 1000; //0.1%
// 		} else {
// 			uint exponentWithPrec = USDsInOutRatio - uint(12).mul(USDsInOutRatioPrecision).div(10);
// 			if (exponentWithPrec >= 2^32) {
// 				return swapFeePresion;
// 			}
// 			(uint powResWithPrec, uint8 powResPrec) = BancorFormula(BancorFormulaAddr_).power(swapFee_A, swapFee_A_Prec, uint32(exponentWithPrec), uint32(USDsInOutRatioPrecision));
// 			uint toReturn = uint(powResWithPrec >> powResPrec).mul(swapFeePresion).div(100);
// 			if (toReturn >= swapFeePresion) {
// 				return swapFeePresion;
// 			} else {
// 				return toReturn;
// 			}
// 		}
// 	}

// 	function redeemView(
// 		address collaAddr,
// 		uint USDsAmt,
//         address oracleAddr,
//         uint chiPrec,
//         uint swapFeePresion,
//         bool swapfeeOutAllowed, uint swapFee_A, uint swapFee_A_Prec, uint swapFee_theta, uint swapFee_theta_Prec,
//         address BancorFormulaAddr_,
//         uint startBlockHeight, uint chiInit, uint chi_alpha, uint chi_alpha_Prec, uint chi_beta_Prec, uint chi_beta,
//         uint chi_gamma, uint chi_gamma_Prec, uint collateralRatio_
// 	) public returns (uint SPAMintAmt, uint collaUnlockAmt, uint USDsBurntAmt, uint swapFeeAmount) {
// 		uint priceColla = IOracle(oracleAddr).collatPrice(collaAddr);
// 		uint precisionColla = IOracle(oracleAddr).collatPricePrecision(collaAddr);
// 		uint priceSPA = IOracle(oracleAddr).getSPAPrice();
// 		uint precisionSPA = IOracle(oracleAddr).SPAPricePrecision();
// 		uint swapFee = calculateSwapFeeOut(swapfeeOutAllowed, swapFee_A, oracleAddr, swapFee_A_Prec, swapFeePresion, swapFee_theta, swapFee_theta_Prec, BancorFormulaAddr_);
// 		uint collaAddrDecimal = uint(ERC20Upgradeable(collaAddr).decimals());
// 		SPAMintAmt = USDsAmt.mul((chiPrec - chiRedeem(oracleAddr, startBlockHeight, chiInit, chi_gamma, chi_gamma_Prec, collateralRatio_,
//         chiPrec, chi_alpha, chi_alpha_Prec, chi_beta_Prec, chi_beta)).mul(precisionSPA)).div(priceSPA.mul(chiPrec));
// 		if (swapFee > 0) {
// 			SPAMintAmt = SPAMintAmt.sub(SPAMintAmt.mul(swapFee).div(swapFeePresion));
// 		}

// 		//Unlock collaeral
// 		uint collaUnlockAmt_18 = USDsAmt.mul(chiMint(oracleAddr, startBlockHeight, chiInit, chiPrec, chi_alpha, chi_alpha_Prec, chi_beta_Prec, chi_beta).mul(precisionColla)).div(chiPrec.mul(priceColla));
// 		collaUnlockAmt = collaUnlockAmt_18.div(10**(uint(18).sub(collaAddrDecimal)));
// 		if (swapFee > 0) {
// 			collaUnlockAmt = collaUnlockAmt.sub(collaUnlockAmt.mul(swapFee).div(swapFeePresion));
// 		}

// 		//Burn USDs
// 		swapFeeAmount = USDsAmt.mul(swapFee).div(swapFeePresion);
// 		USDsBurntAmt =  USDsAmt.sub(swapFeeAmount);
// 	}

// 	/**
// 	 * @dev calculate the InSwap fee, i.e. fees for minting USDs
// 	 * @return the InSwap fee
// 	 */
// 	function calculateSwapFeeIn(
//         bool swapfeeInAllowed, uint swapFee_p, address oracleAddr, uint swapFee_p_Prec, uint swapFeePresion, uint swapFee_theta, uint swapFee_theta_Prec
//     ) public returns (uint) {
// 		// if InSwap fee is disabled, return 0
// 		if (!swapfeeInAllowed) {
// 			return 0;
// 		}

// 		// implement the formula in Section 4.3.1 of whitepaper 
// 		uint priceUSDs_Average = IOracle(oracleAddr).getUSDsPrice_Average(); //TODO: change to 3 days average
// 		uint precisionUSDs = IOracle(oracleAddr).USDsPricePrecision();
// 		uint smallPwithPrecision = swapFee_p.mul(precisionUSDs).div(swapFee_p_Prec);
// 		if (smallPwithPrecision < priceUSDs_Average) {
// 			return swapFeePresion / 1000; // 0.1%
// 		} else {
// 			uint temp = (smallPwithPrecision - priceUSDs_Average).mul(swapFee_theta).div(swapFee_theta_Prec); //precision: precisionUSDs
// 			uint temp2 = temp.mul(temp); //precision: precisionUSDs^2
// 			uint temp3 = temp2.mul(swapFeePresion).div(precisionUSDs).div(precisionUSDs);
// 			uint temp4 = temp3.div(100);
// 			uint temp5 =  swapFeePresion / 1000 + temp4;
// 			if (temp5 >= swapFeePresion) {
// 				return swapFeePresion;
// 			} else {
// 				return temp5;
// 			}
// 		}

// 	}

// 	/**
// 	 * @dev the general mintView function that display all related quantities based on mint types
// 	 *		valueType = 0: mintWithUSDs
// 	 *		valueType = 1: mintWithSPA
// 	 *		valueType = 2: mintWithColla
// 	 *		valueType = 3: mintWithETH
// 	 * @param collaAddr the address of user's chosen collateral
// 	 * @param valueAmt the amount of user input whose specific meaning depends on valueType
// 	 * @param valueType the type of user input whose interpretation is listed above in @dev
// 	 * @return SPABurnAmt the amount of SPA to burn
// 	 *			collaDepAmt the amount of collateral to stake
// 	 *			USDsAmt the amount of USDs to mint
// 	 *			swapFeeAmount the amount of Inswapfee to pay
// 	 */
// 	function mintView(
// 		address collaAddr,
// 		uint valueAmt,
// 		uint8 valueType,
//         address oracleAddr,
//         uint chiPrec,
//         uint swapFeePresion,
//         bool swapfeeInAllowed,
//         uint swapFee_p,
//         uint swapFee_p_Prec,
//         uint swapFee_theta,
//         uint swapFee_theta_Prec,
//         uint startBlockHeight,
//         uint chiInit,
//         uint chi_alpha,
//         uint chi_alpha_Prec,
//         uint chi_beta_Prec,
//         uint chi_beta
// 	) public returns (uint SPABurnAmt, uint collaDepAmt, uint USDsAmt, uint swapFeeAmount) {
// 		// obtain the price and pecision of the collateral
// 		uint priceColla = 0;
// 		uint precisionColla = 0;
// 		if (valueType == 3) {
// 			priceColla = IOracle(oracleAddr).getETHPrice();
// 			precisionColla = IOracle(oracleAddr).ETHPricePrecision();
// 		} else {
// 			priceColla = IOracle(oracleAddr).collatPrice(collaAddr);
// 			precisionColla = IOracle(oracleAddr).collatPricePrecision(collaAddr);
// 		}
// 		// obtain other necessary data
// 		uint priceSPA = IOracle(oracleAddr).getSPAPrice();
// 		uint precisionSPA = IOracle(oracleAddr).SPAPricePrecision();
// 		uint swapFee = calculateSwapFeeIn(
//             swapfeeInAllowed,
//             swapFee_p,
//             oracleAddr,
//             swapFee_p_Prec,
//             swapFeePresion,
//             swapFee_theta,
//             swapFee_theta_Prec
//         );
// 		uint collaAddrDecimal = uint(ERC20Upgradeable(collaAddr).decimals());

// 		if (valueType == 0) { // when mintWithUSDs
// 			// calculate USDsAmt
// 			USDsAmt = valueAmt;
// 			// calculate SPABurnAmt
// 			SPABurnAmt = USDsAmt.mul(chiPrec - chiMint(oracleAddr, startBlockHeight, chiInit, chiPrec, chi_alpha, chi_alpha_Prec, chi_beta_Prec, chi_beta)).mul(precisionSPA).div(priceSPA.mul(chiPrec));
// 			if (swapFee > 0) {
// 				SPABurnAmt = SPABurnAmt.add(SPABurnAmt.mul(swapFee).div(swapFeePresion));
// 			}
// 			// calculate collaDepAmt
// 			uint collaDepAmt_18 = USDsAmt.mul(chiMint(oracleAddr, startBlockHeight, chiInit, chiPrec, chi_alpha, chi_alpha_Prec, chi_beta_Prec, chi_beta)).mul(precisionColla).div(chiPrec.mul(priceColla));
// 			collaDepAmt = collaDepAmt_18.div(10**(uint(18).sub(collaAddrDecimal)));
// 			if (swapFee > 0) {
// 				collaDepAmt = collaDepAmt.add(collaDepAmt.mul(swapFee).div(swapFeePresion));
// 			}
// 			// calculate swapFeeAmount
// 			swapFeeAmount = USDsAmt.mul(swapFee).div(swapFeePresion);

// 		} else if (valueType == 1) { // when mintWithSPA
// 			// calculate SPABurnAmt
// 			SPABurnAmt = valueAmt;
// 			// calculate USDsAmt
// 			USDsAmt = SPABurnAmt;
// 			if (swapFee > 0) {
// 				USDsAmt = USDsAmt.mul(swapFeePresion).div(swapFeePresion.add(swapFee));
// 			}
// 			USDsAmt = USDsAmt.mul(chiPrec).mul(priceSPA).div(precisionSPA.mul(chiPrec - chiMint(oracleAddr, startBlockHeight, chiInit, chiPrec, chi_alpha, chi_alpha_Prec, chi_beta_Prec, chi_beta)));
// 			// calculate collaDepAmt
// 			uint collaDepAmt_18 = USDsAmt.mul(chiMint(oracleAddr, startBlockHeight, chiInit, chiPrec, chi_alpha, chi_alpha_Prec, chi_beta_Prec, chi_beta)).mul(precisionColla).div(chiPrec.mul(priceColla));
// 			collaDepAmt = collaDepAmt_18.div(10**(uint(18).sub(collaAddrDecimal)));
// 			if (swapFee > 0) {
// 				collaDepAmt = collaDepAmt.add(collaDepAmt.mul(swapFee).div(swapFeePresion));
// 			}
// 			// calculate swapFeeAmount
// 			swapFeeAmount = USDsAmt.mul(swapFee).div(swapFeePresion);

// 		} else if (valueType == 2 || valueType == 3) { // when mintWithColla or mintWithETH
// 			// calculate collaDepAmt
// 			collaDepAmt = valueAmt;
// 			// calculate USDsAmt
// 			USDsAmt = collaDepAmt;
// 			if (swapFee > 0) {
// 				USDsAmt = USDsAmt.mul(swapFeePresion).div(swapFeePresion.add(swapFee));
// 			}
// 			uint CollaDepAmt_18 = USDsAmt.mul(10**(uint(18).sub(collaAddrDecimal)));
// 			USDsAmt = CollaDepAmt_18.mul(chiPrec.mul(priceColla)).div(precisionColla).div(chiMint(oracleAddr, startBlockHeight, chiInit, chiPrec, chi_alpha, chi_alpha_Prec, chi_beta_Prec, chi_beta));
// 			// calculate SPABurnAmt
// 			SPABurnAmt = USDsAmt.mul(chiPrec - chiMint(oracleAddr, startBlockHeight, chiInit, chiPrec, chi_alpha, chi_alpha_Prec, chi_beta_Prec, chi_beta)).mul(precisionSPA).div(priceSPA.mul(chiPrec));
// 			if (swapFee > 0) {
// 				SPABurnAmt = SPABurnAmt.add(SPABurnAmt.mul(swapFee).div(swapFeePresion));
// 			}
// 			// calculate swapFeeAmount
// 			swapFeeAmount = USDsAmt.mul(swapFee).div(swapFeePresion);
// 		}
// 	}
// }
