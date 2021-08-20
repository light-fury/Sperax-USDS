pragma solidity ^0.6.12;

import "@openzeppelin/contracts-upgradeable/proxy/Initializable.sol";
import { USDs } from "../token/USDs.sol";
import { BancorFormula } from "../libraries/BancorFormula.sol";
import { VaultLibrary } from "../libraries/VaultLibrary.sol";

contract VaultStorage {
	event AssetSupported(address _asset);

	bool public mintRedeemAllowed;	// if false, no USDs can be minted or burnt
	bool public capitalAllowed;		// if false, no collaterals can be reinvested

	bool public swapfeeInAllowed;
	bool public swapfeeOutAllowed;

	mapping(address => uint) public supportedCollatAmount;	// the total amount of some supported collateral users have staked 	
	mapping(address => bool) public supportedCollat;		// if it is true, the collateral is supported; else it is false, it is not supported
	mapping(address => address) public assetDefaultStrategies;	// the corresponding strategy contract address to a supported collateral token (currently, they are all AAVE)
	address[] allCollat;	// the list of all supported collaterals
	address[] allStrategies;	// the list of all strategy addresses
	mapping (address => mapping (address => uint)) public strategiesAllocatedAmt; // the amount of a specific collateral re-invested by a chosen strategy

	address public SPATokenAddr;
	address public oracleAddr;
	address public collaValut;	// the contract address that stores all collaterals
								// WARNING: currently, this address is the same as the address of VaultCore.sol
	address public SPAValut;	
	address public USDsFeeValut;	// the account that stores all swapping fees
	address public USDsYieldValut;	// TO DELETE

	uint public startBlockHeight;

	// the following constant economic parameters are subject to changes
	uint public constant chi_alpha = 513;
	uint public constant chi_alpha_Prec = 10**12;
	uint public constant chiPrec = chi_alpha_Prec;
	uint public constant chiInit = chiPrec * 100 / 95;
	uint public constant chi_beta = 9;
	uint public constant chi_beta_Prec = 1;
	uint public constant chi_gamma = 1;
	uint public constant chi_gamma_Prec = 1;


	uint public constant swapFeePresion = 1000000;
	uint public constant swapFee_p = 99;
	uint public constant swapFee_p_Prec = 100;
	uint public constant swapFee_theta = 50;
	uint public constant swapFee_theta_Prec = 1;
	uint32 public constant swapFee_a = 12;
	uint32 public constant swapFee_a_Prec = 10;
	uint public constant swapFee_A = 20;
	uint public constant swapFee_A_Prec = 1;

	uint public constant allocatePrecentage = 8;
	uint public constant allocatePrecentage_Prec = 10;

	USDs USDsInstance;
	BancorFormula BancorInstance;

}
