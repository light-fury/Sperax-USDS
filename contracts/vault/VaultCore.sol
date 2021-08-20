//TO-DO: check source file of SafeMathUpgradeable regarding trySub() (and the usage of "unchecked")
//TO-DO: check ERC20Upgradeable vs ERC20Upgradeable
// Note: assuming when exponentWithPrec >= 2^32, toReturn >= swapFeePresion () (TO-DO: work out the number)
//TO-DO: AAVE in progress
//TO-DO: deal with assetDefaultStrategies
//TO-DO: what happen when we redeem aTokens
//TO-DO: whether _redeem needs "SafeTransferFrom" and how
//TO-DO: check all user inputs, especially mintView
pragma solidity ^0.6.12;

import "@openzeppelin/contracts-upgradeable/proxy/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";

import "../libraries/MyMath.sol";
import "../libraries/Helpers.sol";
import "../interfaces/IOracle.sol";
import "../interfaces/ISperaxToken.sol";
import "../interfaces/IStrategy.sol";
import "../interfaces/IVault.sol";
import "../libraries/StableMath.sol";
import { USDs } from "../token/USDs.sol";
import { VaultStorage } from "./VaultStorage.sol";
import { VaultLibrary } from "../libraries/VaultLibrary.sol";
import { BancorFormula } from "../libraries/BancorFormula.sol";

contract VaultCore is Initializable, OwnableUpgradeable, VaultStorage {
	using SafeERC20Upgradeable for ERC20Upgradeable;
	using SafeMathUpgradeable for uint;
	using MyMath for uint;
	using StableMath for uint;

	modifier whenMintRedeemAllowed {
		require(mintRedeemAllowed, "Mint & redeem paused");
		_;
	}
	/**
	 * @dev check if re-investment of collaterals is allowed
	 */
	modifier whenNotCapitalPaused {
		require(capitalAllowed, "Allocate paused");
		_;
	}
	/**
	 * @dev disable USDs mint & redeem
	 */
	function updateMintBurn(bool _mintRedeemAllowed) external onlyOwner {
		mintRedeemAllowed = _mintRedeemAllowed;
	}
	/**
	 * @dev disable collateral re-investment
	 */
	function updateAllocate(bool _capitalAllowed) external onlyOwner {
		capitalAllowed = _capitalAllowed;
	}
	/**
	 * @dev disable swapInFee, i.e. mint becomes free
	 */
	function updateSwapInFee(bool _swapfeeInAllowed) external onlyOwner {
		swapfeeInAllowed = _swapfeeInAllowed;
	}
	/**
	 * @dev disable swapOutFee, i.e. redeem becomes free
	 */
	function updateSwapOutFee(bool _swapfeeOutAllowed) external onlyOwner {
		swapfeeOutAllowed = _swapfeeOutAllowed;
	}

	/**
	 * @dev add a new supported collateral
	 * @param _asset the address of the new supported collateral
	 */
	function supportAsset(address _asset) external onlyOwner {
		require(!supportedCollat[_asset], "Asset already supported");
		supportedCollat[_asset] = true;
		allCollat.push(_asset);
		// TO-DO: add Oracle support here;
	}

	//INITIALIZER

	function initialize(address USDsToken_, address oracleAddr_, address BancorFormulaAddr_) public initializer {
		OwnableUpgradeable.__Ownable_init();
		// Initialize variables
		mintRedeemAllowed = true;
		swapfeeInAllowed = true;
		swapfeeOutAllowed = true;
		capitalAllowed = true;
		SPATokenAddr = 0x2B607b664A1012aD658b430E03603be1DC83EeCc;	// SPA on Kovan

		collaValut = address(this);
		SPAValut = address(this);
		USDsFeeValut = address(this);
		USDsYieldValut = address(this);	// TO DELETE
		supportedCollat[0xb7a4F3E9097C08dA09517b5aB877F7a917224ede] = true;	// USDC on Kovan
		allCollat.push(0xb7a4F3E9097C08dA09517b5aB877F7a917224ede);
		supportedCollat[0x4F96Fe3b7A6Cf9725f59d353F723c1bDb64CA6Aa] = true;	// Dai on Kovan
		allCollat.push(0x4F96Fe3b7A6Cf9725f59d353F723c1bDb64CA6Aa);
		supportedCollat[0x07de306FF27a2B630B1141956844eB1552B956B5] = true;	// USDT on Kovan
		allCollat.push(0x07de306FF27a2B630B1141956844eB1552B956B5);
		USDsInstance = USDs(USDsToken_);
		oracleAddr = oracleAddr_;
		BancorInstance = BancorFormula(BancorFormulaAddr_);
		startBlockHeight = block.number;
	}

	//View functions

	/**
	 * @dev view related quantities for minting USDs with USDs amount
	 * @param collaAddr the address of user's chosen collateral
	 * @param USDsMintAmt the amount of USDs to mint
	 * @return SPABurnAmt the amount of SPA to burn
	 *			collaDepAmt the amount of collateral to stake
	 *			USDsAmt the amount of USDs to mint
	 *			swapFeeAmount the amount of Inswapfee to pay
	 */
	function mintWithUSDsView(address collaAddr, uint USDsMintAmt)
		public returns (uint SPABurnAmt, uint collaDepAmt, uint USDsAmt, uint swapFeeAmount)
	{
		require(supportedCollat[collaAddr], "Collateral not supported");
		require(USDsMintAmt > 0, "Amount needs to be greater than 0");
		(SPABurnAmt, collaDepAmt, USDsAmt, swapFeeAmount) = VaultLibrary.mintView(collaAddr, USDsMintAmt, 0,
			oracleAddr,
			chiPrec,
			swapFeePresion,
			swapfeeInAllowed,
			swapFee_p,
			swapFee_p_Prec,
			swapFee_theta,
			swapFee_theta_Prec,
			startBlockHeight,
			chiInit,
			chi_alpha,
			chi_alpha_Prec,
			chi_beta_Prec,
			chi_beta);
	}
	/**
	 * @dev view related quantities for minting USDs with SPA amount to burn
	 * @param collaAddr the address of user's chosen collateral
	 * @param SPAAmt the amount of SPAs to burn
	 * @return SPABurnAmt the amount of SPA to burn
	 *			collaDepAmt the amount of collateral to stake
	 *			USDsAmt the amount of USDs to mint
	 *			swapFeeAmount the amount of Inswapfee to pay
	 */
	function mintWithSPAView(address collaAddr, uint SPAAmt)
		public returns (uint SPABurnAmt, uint collaDepAmt, uint USDsAmt, uint swapFeeAmount)
	{
		require(supportedCollat[collaAddr], "Collateral not supported");
		require(SPAAmt > 0, "Amount needs to be greater than 0");
		(SPABurnAmt, collaDepAmt, USDsAmt, swapFeeAmount)  = VaultLibrary.mintView(collaAddr, SPAAmt, 1,
			oracleAddr,
			chiPrec,
			swapFeePresion,
			swapfeeInAllowed,
			swapFee_p,
			swapFee_p_Prec,
			swapFee_theta,
			swapFee_theta_Prec,
			startBlockHeight,
			chiInit,
			chi_alpha,
			chi_alpha_Prec,
			chi_beta_Prec,
			chi_beta);
	}
	/**
	 * @dev view related quantities for minting USDs with collateral amount to stake (excluding ETH)
	 * @param collaAddr the address of user's chosen collateral
	 * @param CollaAmt the amount of collateral to stake
	 * @return SPABurnAmt the amount of SPA to burn
	 *			collaDepAmt the amount of collateral to stake
	 *			USDsAmt the amount of USDs to mint
	 *			swapFeeAmount the amount of Inswapfee to pay
	 */
	function mintWithCollaView(address collaAddr, uint CollaAmt)
		public returns (uint SPABurnAmt, uint collaDepAmt, uint USDsAmt, uint swapFeeAmount)
	{
		require(supportedCollat[collaAddr], "Collateral not supported");
		require(CollaAmt > 0, "Amount needs to be greater than 0");
		(SPABurnAmt, collaDepAmt, USDsAmt, swapFeeAmount) = VaultLibrary.mintView(collaAddr, CollaAmt, 2,
			oracleAddr,
			chiPrec,
			swapFeePresion,
			swapfeeInAllowed,
			swapFee_p,
			swapFee_p_Prec,
			swapFee_theta,
			swapFee_theta_Prec,
			startBlockHeight,
			chiInit,
			chi_alpha,
			chi_alpha_Prec,
			chi_beta_Prec,
			chi_beta);
	}

	/**
	 * @dev view related quantities for minting USDs with ETH
	 * @param CollaAmt the amount of ETH that the user stakes for minting USDs
	 * @return SPABurnAmt the amount of SPA to burn
	 *			collaDepAmt the amount of collateral to stake
	 *			USDsAmt the amount of USDs to mint
	 *			swapFeeAmount the amount of Inswapfee to pay
	 *
	 * SPABurnAmt precision: 10^18
	 * collaDepAmt precision: 10^collaAddrDecimal
	 * USDsAmt precision: 10^18
	 * swapFeeAmount precision: swapFeePresion
	 */
	function mintWithEthView(uint CollaAmt)
		public returns (uint SPABurnAmt, uint collaDepAmt, uint USDsAmt, uint swapFeeAmount)
	{
		require(CollaAmt > 0, "Amount needs to be greater than 0");
		(SPABurnAmt, collaDepAmt, USDsAmt, swapFeeAmount) = VaultLibrary.mintView(address(0), CollaAmt, 3,
			oracleAddr,
			chiPrec,
			swapFeePresion,
			swapfeeInAllowed,
			swapFee_p,
			swapFee_p_Prec,
			swapFee_theta,
			swapFee_theta_Prec,
			startBlockHeight,
			chiInit,
			chi_alpha,
			chi_alpha_Prec,
			chi_beta_Prec,
			chi_beta);
	}

	/**
	 * @dev mint USDs by entering USDs amount
	 * @param collaAddr the address of user's chosen collateral
	 * @param USDsMintAmt the amount of USDs to be minted
	 */
	function mintWithUSDs(address collaAddr, uint USDsMintAmt)
		public
		whenMintRedeemAllowed
	{
		require(supportedCollat[collaAddr], "Collateral not supported");
		require(USDsMintAmt > 0, "Amount needs to be greater than 0");
		_mint(collaAddr, USDsMintAmt, 0);
	}

	/**
	 * @dev mint USDs by entering SPA amount
	 * @param collaAddr the address of user's chosen collateral
	 * @param SPAAmt the amount of SPA to burn
	 */
	function mintWithSPA(address collaAddr, uint SPAAmt)
		public
		whenMintRedeemAllowed
	{
		require(supportedCollat[collaAddr], "Collateral not supported");
		require(SPAAmt > 0, "Amount needs to be greater than 0");
		_mint(collaAddr, SPAAmt, 1);
	}

	/**
	 * @dev mint USDs by entering collateral amount (excluding ETH)
	 * @param collaAddr the address of user's chosen collateral
	 * @param CollaAmt the amount of collateral to stake
	 */
	function mintWithColla(address collaAddr, uint CollaAmt)
		public
		whenMintRedeemAllowed
	{
		require(supportedCollat[collaAddr], "Collateral not supported");
		require(CollaAmt > 0, "Amount needs to be greater than 0");
		_mint(collaAddr, CollaAmt, 2);
	}

	/**
	 * @dev mint USDs by ETH
	 * note: this function needs changes when USDs is deployed on other blockchain platform
	 */
	function mintWithEth() public payable whenMintRedeemAllowed {
    require(msg.value > 0, "Need to pay Ether");
		_mint(address(0), msg.value, 3);
	}

	function _mint(
		address collaAddr,
		uint valueAmt,
		uint8 valueType
	) internal whenMintRedeemAllowed {
		(uint SPABurnAmt, uint collaDepAmt, uint USDsAmt, uint swapFeeAmount) = VaultLibrary.mintView(collaAddr, valueAmt, valueType,
			oracleAddr,
			chiPrec,
			swapFeePresion,
			swapfeeInAllowed,
			swapFee_p,
			swapFee_p_Prec,
			swapFee_theta,
			swapFee_theta_Prec,
			startBlockHeight,
			chiInit,
			chi_alpha,
			chi_alpha_Prec,
			chi_beta_Prec,
			chi_beta);
		ISperaxToken(SPATokenAddr).burnFrom(msg.sender, SPABurnAmt);
		if (valueType != 3) {
			ERC20Upgradeable(collaAddr).safeTransferFrom(msg.sender, collaValut, collaDepAmt);
		}
		USDsInstance.mint(msg.sender, USDsAmt);
		USDsInstance.mint(USDsFeeValut, swapFeeAmount);

		supportedCollatAmount[collaAddr] = supportedCollatAmount[collaAddr].add(collaDepAmt);
		//emit USDSMinted(msg.sender, USDsAmt, SPABurnAmt, swapFeeAmount);
	}

	function redeem(address collaAddr, uint USDsAmt)
		public
		whenMintRedeemAllowed
	{
		require(supportedCollat[collaAddr], "Collateral not supported");
		require(USDsAmt > 0, "Amount needs to be greater than 0");
		_redeem(collaAddr, USDsAmt);
	}
	
	//
	// /**
	//  * @dev  Precision: same as chi (chiPrec)
	//  */
	//
	function collateralRatio() public returns (uint ratio) {
    uint totalValueLocked = _totalValueLocked();
		uint USDsSupply =  USDsInstance.totalSupply();
		uint priceUSDs = uint(IOracle(oracleAddr).getUSDsPrice());
		uint precisionUSDs = IOracle(oracleAddr).USDsPricePrecision();
		uint USDsValue = USDsSupply.mul(priceUSDs).div(precisionUSDs);
		ratio = totalValueLocked.mul(chiPrec).div(USDsValue);
  }


	function _redeem(
		address collaAddr,
		uint USDsAmt
	) internal whenMintRedeemAllowed {
		uint collateralRatio_ = collateralRatio();
		(uint SPAMintAmt, uint collaUnlockAmt, uint USDsBurntAmt, uint swapFeeAmount) = VaultLibrary.redeemView(collaAddr, USDsAmt,
        oracleAddr,
        chiPrec,
        swapFeePresion,
        swapfeeOutAllowed, swapFee_A, swapFee_A_Prec, swapFee_theta, swapFee_theta_Prec,
        address(BancorInstance),
        startBlockHeight, chiInit, chi_alpha, chi_alpha_Prec, chi_beta_Prec, chi_beta,
        chi_gamma, chi_gamma_Prec, collateralRatio_);

		ISperaxToken(SPATokenAddr).mintForUSDs(msg.sender, SPAMintAmt);
		ERC20Upgradeable(collaAddr).safeTransfer(msg.sender, collaUnlockAmt);
		supportedCollatAmount[collaAddr] = supportedCollatAmount[collaAddr].sub(collaUnlockAmt);
		USDsInstance.burn(msg.sender, USDsBurntAmt);
		USDsInstance.transferFrom(msg.sender, USDsFeeValut, swapFeeAmount);

		//emit USDSRedeemed(msg.sender, USDsBurntAmt, SPAMintAmt, swapFeeAmount);
	}

	/**
	 * @dev Calculate the total value of assets held by the Vault and all
	 *      strategies and update the supply of USDs.
	 */
	function rebase() external onlyOwner {
		_rebase();
	}

	/**
	 * @dev Calculate the total value of assets held by the Vault and all
	 *      strategies and update the supply of USDs, optionaly sending a
	 *      portion of the yield to the trustee.
	 */
	function _rebase() internal {
		address _strategyAddr;
		IStrategy strategy;
		address collaAddr;
		uint allocatedAmt;
		uint newTokensAmt;
		uint USDsSupplyIncrement;
		uint USDsSupplyIncrementTotal;
		for (uint y = 0; y < allCollat.length; y++) {
			collaAddr = allCollat[y];
			for (uint i = 0; i < allStrategies.length; i++) {
				_strategyAddr = allStrategies[i];
				strategy = IStrategy(_strategyAddr);
				allocatedAmt = strategiesAllocatedAmt[collaAddr][_strategyAddr] ;
				(, newTokensAmt) = strategy.checkBalance(collaAddr).trySub(allocatedAmt);
				if (newTokensAmt > 0) {
					strategy.withdraw(address(this), collaAddr, newTokensAmt);
					(uint SPABurnAmt, uint collaDepAmt, uint USDsAmt, uint swapFeeAmount) = VaultLibrary.mintView(collaAddr, newTokensAmt, 2,
						oracleAddr,
						chiPrec,
						swapFeePresion,
						swapfeeInAllowed,
						swapFee_p,
						swapFee_p_Prec,
						swapFee_theta,
						swapFee_theta_Prec,
						startBlockHeight,
						chiInit,
						chi_alpha,
						chi_alpha_Prec,
						chi_beta_Prec,
						chi_beta);
					//strategy.withdraw(address(this), collaAddr, collaDepAmt);
					ISperaxToken(SPATokenAddr).burnFrom(SPAValut, SPABurnAmt);
					USDsSupplyIncrement = USDsInstance._totalSupply().add(USDsAmt).add(swapFeeAmount);
					USDsSupplyIncrementTotal = USDsSupplyIncrementTotal.add(USDsSupplyIncrement);
				}
				USDsInstance.changeSupply(USDsSupplyIncrementTotal);
		   }
		}
	}

	function totalValueLocked() external view returns (uint value) {
		value = _totalValueLocked();
	}

	function _totalValueLocked() internal view returns (uint value) {
		value = _totalValueInVault().add(_totalValueInStrategies());
	}

	function totalValueInVault() external view returns (uint value) {
		value = _totalValueInVault();
	}

	function _totalValueInVault() internal view returns (uint value) {
		address collaAddr;
		uint priceColla = 0;
		uint precisionColla = 0;
		uint collaAddrDecimal = 0;
		uint collaTotalValueInVault = 0;
		uint collaTotalValueInVault_18 = 0;
		for (uint y = 0; y < allCollat.length; y++) {
			collaAddr = allCollat[y];
			priceColla = IOracle(oracleAddr).collatPrice(collaAddr);
			precisionColla = IOracle(oracleAddr).collatPricePrecision(collaAddr);
			collaAddrDecimal = uint(ERC20Upgradeable(collaAddr).decimals());
			collaTotalValueInVault = ERC20Upgradeable(collaAddr).balanceOf(address(this)).mul(priceColla).div(precisionColla);
			collaTotalValueInVault_18 = collaTotalValueInVault.mul(10**(uint(18).sub(collaAddrDecimal)));
			value = value.add(collaTotalValueInVault_18);
		}
	}

	function totalValueInStrategies() external view returns (uint value) {
		value = _totalValueInStrategies();
	}

	function _totalValueInStrategies() internal view returns (uint value) {
		for (uint i = 0; i < allStrategies.length; i++) {
		   value = value.add(_totalValueInStrategy(allStrategies[i]));
	   }
	}


	function _totalValueInStrategy(address _strategyAddr) internal view returns (uint value) {
		IStrategy strategy = IStrategy(_strategyAddr);
		address collaAddr;
		uint priceColla = 0;
		uint precisionColla = 0;
		uint collaAddrDecimal = 0;
		uint collaTotalValueInStrategy = 0;
		uint collaTotalValueInStrategy_18 = 0;
		for (uint y = 0; y < allCollat.length; y++) {
			collaAddr = allCollat[y];
			if (strategy.supportsAsset(collaAddr)) {
				priceColla = IOracle(oracleAddr).collatPrice(collaAddr);
				precisionColla = IOracle(oracleAddr).collatPricePrecision(collaAddr);
				collaAddrDecimal = uint(ERC20Upgradeable(collaAddr).decimals());
				collaTotalValueInStrategy = strategy.checkBalance(allCollat[y]).mul(priceColla).div(precisionColla);
				collaTotalValueInStrategy_18 = collaTotalValueInStrategy.mul(10**(uint(18).sub(collaAddrDecimal)));
				value = value.add(collaTotalValueInStrategy_18);
			}
		}
	}

	/**
     * @notice Allocate unallocated funds on Vault to strategies.
     * @dev Allocate unallocated funds on Vault to strategies.
		**/
	function allocate() external whenNotCapitalPaused {
		_allocate();
	}

	/**
		* @notice Allocate unallocated funds on Vault to strategies.
		* @dev Allocate unallocated funds on Vault to strategies.
		**/
	function _allocate() internal {
		// Iterate over all assets in the Vault and allocate the the appropriate
		// strategy
		for (uint i = 0; i < allCollat.length; i++) {
			address collateralAddr = allCollat[i];
			ERC20Upgradeable collateralERC20 = ERC20Upgradeable(collateralAddr);
			uint collatInVault = collateralERC20.balanceOf(address(this));
			uint collatInVaultTotal = supportedCollatAmount[allCollat[i]];
			(,uint allocateAmount) = collatInVaultTotal.mul(allocatePrecentage).div(allocatePrecentage_Prec).trySub(collatInVault);

			address depositStrategyAddr = assetDefaultStrategies[collateralAddr];

			if (depositStrategyAddr != address(0) && allocateAmount > 0) {
				IStrategy strategy = IStrategy(depositStrategyAddr);
				collateralERC20.safeTransfer(address(strategy), allocateAmount);
				strategy.deposit(collateralAddr, allocateAmount);
				strategiesAllocatedAmt[collateralAddr][depositStrategyAddr] = strategiesAllocatedAmt[collateralAddr][depositStrategyAddr].add(allocateAmount);
			}
		}
	}

}
