pragma solidity >=0.8.0 <0.9.0;
// SPDX-License-Identifier: MIT

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

/**
 * @title DEX
 * @author stevepham.eth and m00npapi.eth
 * @notice this is a single token pair reserves DEX, ref: "Scaffold-ETH Challenge 4" as per https://speedrunethereum.com/, README.md and full branch (front-end) made with lots of inspiration from pre-existing example repos in scaffold-eth organization.
 */
contract DEX {
    /* ========== GLOBAL VARIABLES ========== */

    uint256 public totalLiquidity; // Total amount of liquidity provider tokens (LPTs) minted (NOTE: That LPT "price" is tied to the ratio, and thus price of the assets within this AMM)
    mapping(address => uint256) public liquidity; // Liquidity of each depositor
    using SafeMath for uint256; // Use of SafeMath for uint256 variables
    IERC20 token; // Instantiates the imported contract

    /* ========== EVENTS ========== */

    event EthToTokenSwap(address swapper, string txDetails, uint256 ethInput, uint256 tokenOutput);
    event TokenToEthSwap(address swapper, string txDetails, uint256 tokensInput, uint256 ethOutput);
    // Emitted when liquidity provided to DEX and mints LPTs.
    event LiquidityProvided(address liquidityProvider, uint256 tokensInput, uint256 ethInput, uint256 liquidityMinted);
    // Emitted when liquidity removed from DEX and decreases LPT count within DEX
    event LiquidityRemoved(
        address liquidityRemover,
        uint256 tokensOutput,
        uint256 ethOutput,
        uint256 liquidityWithdrawn
    );

    /* ========== CONSTRUCTOR ========== */

    constructor(address token_addr) public {
        token = IERC20(token_addr); // Specifies the token address that will hook into the interface and be used through the variable 'token'
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    /**
     * @notice Initializes amount of tokens that will be transferred to the DEX itself from the erc20 contract mintee (and only them based on how Balloons.sol is written). Loads contract up with both ETH and Balloons.
     * @param tokens amount to be transferred to DEX
     * @return totalLiquidity is the number of LPTs minting as a result of deposits made to DEX contract
     * NOTE: since ratio is 1:1, this is fine to initialize the totalLiquidity (wrt to balloons) as equal to eth balance of contract.
     */
    function init(uint256 tokens) public payable returns (uint256) {
        require(totalLiquidity == 0, "DEX: init - already has liquidity");
        totalLiquidity = address(this).balance;
        liquidity[msg.sender] = totalLiquidity;
        require(token.transferFrom(msg.sender, address(this), tokens), "DEX: init - transfer did not transact");
        return totalLiquidity;
    }

    /**
     * @notice Calculate price based on the amount of ETH or balloons you want to pay (xInput) and the amount of tokens and ETH already in the contract (xReserves, yReserves)
     * Returns yOutput (or yDelta) for xInput (or xDelta)
     */
    function price(
        uint256 xInput,
        uint256 xReserves,
        uint256 yReserves
    ) public view returns (uint256 yOutput) {
        uint256 xInputWithFee = xInput.mul(997); // Deducting 0.3% fee from input. Multiplying by 997 to avoid floating point errors.
        uint256 numerator = xInputWithFee.mul(yReserves); // Input reserve. E.g., if paying 1 ETH, then this would be 0.997 ETH * 5 balloons (if 5 balloons in contract)
        uint256 denominator = (xReserves.mul(1000)).add(xInputWithFee); // Output reserve. 5 ETH (if 5 ETH in contract) + 0.997 ETH (if 1 ETH in input). Multiplication by 1000 to avoid floating point errors.
        return (numerator / denominator); // Ratio of input reserve to output reserve to calculate the final price: (0.997 ETH * 5 balloons) / (5 ETH + 0.997 ETH) = 0.831248 balloons for 1 ETH paid
    }

    /**
     * @notice Returns liquidity for a user. Note this is not needed typically due to the `liquidity()` mapping variable being public and having a getter as a result. This is left though as it is used within the front end code (App.jsx).
     */
    function getLiquidity(address lp) public view returns (uint256) {
        return liquidity[lp];
    }

    /**
     * @notice Sends Ether to DEX in exchange for $BAL
     * How many balloons you can get for the given amount of ETH
     */
    function ethToToken() public payable returns (uint256 tokenOutput) {
        require(msg.value > 0, "Cannot swap 0 ETH");
        uint256 ethReserve = address(this).balance.sub(msg.value); // Subtracting the amount of ETH sent from the contract's ETH balance, to get the amount of ETH that was in the contract before the transaction, which is the real ETH reserve
        uint256 token_reserve = token.balanceOf(address(this));
        uint256 tokenOutput = price(msg.value, ethReserve, token_reserve); // Calculate the amount of tokens that will be minted

        require(token.transfer(msg.sender, tokenOutput), "ethToToken(): Reverted swap.");
        emit EthToTokenSwap(msg.sender, "ETH to Balloons", msg.value, tokenOutput);
        return tokenOutput;
    }

    /**
     * @notice Sends $BAL tokens to DEX in exchange for Ether
     * How much ETH you can get for the given amount of balloons you want to sell to a DEX
     */
    function tokenToEth(uint256 tokenInput) public returns (uint256 ethOutput) {
        require(tokenInput > 0, "Cannot swap 0 tokens");
        uint256 token_reserve = token.balanceOf(address(this));
        uint256 ethOutput = price(tokenInput, token_reserve, address(this).balance);
        require(token.transferFrom(msg.sender, address(this), tokenInput), "tokenToEth(): Reverted swap"); // Transfer the tokens from the sender to the contract
        (bool sent, ) = msg.sender.call{ value: ethOutput }(""); // Send the ETH to the sender
        require(sent, "tokenToEth(): Revert in transferring ETH to you!");
        emit TokenToEthSwap(msg.sender, "Balloons to ETH", ethOutput, tokenInput);
        return ethOutput;
    }

    /**
     * @notice Allows deposits of $BAL and $ETH to liquidity pool
     * NOTE: parameter is the msg.value sent with this function call. That amount is used to determine the amount of $BAL needed as well and taken from the depositor.
     * NOTE: user has to make sure to give DEX approval to spend their tokens on their behalf by calling approve function prior to this function call.
     * NOTE: Equal parts of both assets will be removed from the user's wallet with respect to the price outlined by the AMM.
     * NOTE: LP tokens are a way for liquidity providers to prove their ownership of a certain share of the pool and can be redeemed for the originally deposited assets at any time.
     */
    function deposit() public payable returns (uint256 tokensDeposited) {
        // Because ETH is being deposited into DEX, contract balance is automatically increased by the added amount, but all the calculations need to be performed with ETH reserve from before adding our own ETH
        uint256 ethReserve = address(this).balance.sub(msg.value);
        uint256 tokenReserve = token.balanceOf(address(this));
        uint256 tokenDeposit;

        tokenDeposit = (msg.value.mul(tokenReserve) / ethReserve).add(1);
        uint256 liquidityMinted = msg.value.mul(totalLiquidity) / ethReserve;
        liquidity[msg.sender] = liquidity[msg.sender].add(liquidityMinted);
        totalLiquidity = totalLiquidity.add(liquidityMinted);

        require(token.transferFrom(msg.sender, address(this), tokenDeposit));
        emit LiquidityProvided(msg.sender, liquidityMinted, msg.value, tokenDeposit);
        return tokenDeposit;
    }

    /**
     * @notice allows withdrawal of $BAL and $ETH from liquidity pool
     * NOTE: with this current code, the msg caller could end up getting very little back if the liquidity is super low in the pool. I guess they could see that with the UI.
     */
    function withdraw(uint256 amount) public returns (uint256 eth_amount, uint256 token_amount) {
        require(liquidity[msg.sender] >= amount, "Withdraw: sender does not have enough liquidity to withdraw.");
        uint256 ethReserve = address(this).balance;
        uint256 tokenReserve = token.balanceOf(address(this));
        // How much ETH is removed from the liquidity pool
        uint256 ethWithdrawn;
        ethWithdrawn = amount.mul(ethReserve) / totalLiquidity;
        // How many balloons are removed from the liquidity pool
        uint256 tokenAmount = amount.mul(tokenReserve) / totalLiquidity;
        liquidity[msg.sender] = liquidity[msg.sender].sub(amount);
        totalLiquidity = totalLiquidity.sub(amount);

        (bool sent, ) = payable(msg.sender).call{ value: ethWithdrawn }("");
        require(sent, "withdraw(): revert in transferring eth to you!");
        require(token.transfer(msg.sender, tokenAmount));
        emit LiquidityRemoved(msg.sender, amount, ethWithdrawn, tokenAmount);
        return (ethWithdrawn, tokenAmount);
    }
}
