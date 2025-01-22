pragma solidity ^0.8.0;

import "./ERC20.sol";

abstract contract LiquidityPool is ERC20 {
    address public owner;
    address public token1;
    address public token2;
    
    uint256 public totalLiquidity;
    mapping(address => uint256) public liquidity;
    
    // token1 is the buying token such as LumeCoin or USDT
    // token2 is the fractional asset
    constructor(address _token1, address _token2) {
        owner = msg.sender;
        token1 = _token1;
        token2 = _token2;
    }
    
    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can call this function");
        _;
    }
    
    // Events
    event AddLiquidity(address user, uint256 amountToken1, uint256 amountToken2, uint256 liquidityMinted, uint256 totalLiquidity);
    event WithdrawLiquidity(address user, uint256 token1ToTransfer, uint256 token2ToTransfer, uint256 amountLP, uint256 totalLiquidity);
    event Trade(address user, uint256 amountInput, uint256 amountOutput);
    
    
    // Add liquidity to the pool
    function addLiquidity(uint256 amountToken1, uint256 amountToken2) external {
        require(amountToken1 > 0 && amountToken2 > 0, "Amounts must be greater than zero");
        
        // Check pool balance
        uint256 balanceToken1 = IERC20(token1).balanceOf(address(this));
        uint256 balanceToken2 = IERC20(token2).balanceOf(address(this));
        
        // Transfer tokens to the contract
        IERC20(token1).transferFrom(msg.sender, address(this), amountToken1);
        IERC20(token2).transferFrom(msg.sender, address(this), amountToken2);
        
        // Calculate and mint LP tokens
        uint256 liquidityMinted;
        
        if (totalLiquidity == 0) {
            liquidityMinted = (amountToken1 * amountToken2);  // If it's the first liquidity provider, assign a simple product as LP tokens.
        } else {
            liquidityMinted = (amountToken1 * amountToken2 * totalLiquidity) / (balanceToken1 * balanceToken2);
        }

        require(liquidityMinted > 0, "Insufficient liquidity");

        totalLiquidity += liquidityMinted;
        liquidity[msg.sender] += liquidityMinted;
        
        emit AddLiquidity(msg.sender, amountToken1, amountToken2, liquidityMinted, totalLiquidity);
    }
    
    function withdrawLiquidity(uint256 amountLP) external {
        require(liquidity[msg.sender] >= amountLP, "Insufficient liquidity balance");
        
        // Check pool balances
        uint256 balanceToken1 = IERC20(token1).balanceOf(address(this));
        uint256 balanceToken2 = IERC20(token2).balanceOf(address(this));
        
        // Calculate amount of tokens to transfer
        uint256 token1ToTransfer = (amountLP * balanceToken1) / totalLiquidity;
        uint256 token2ToTransfer = (amountLP * balanceToken2) / totalLiquidity;
        
        require(token1ToTransfer <= balanceToken1, "Insufficient Token1 balance");
        require(token2ToTransfer <= balanceToken2, "Insufficient Token2 balance");
        
        // Update liquidity balances
        liquidity[msg.sender] -= amountLP;
        totalLiquidity -= amountLP;
        
        // Transfer tokens to message sender
        IERC20(token1).transfer(msg.sender, token1ToTransfer);
        IERC20(token2).transfer(msg.sender, token2ToTransfer);
        
        emit WithdrawLiquidity(msg.sender, token1ToTransfer, token2ToTransfer, amountLP, totalLiquidity);
    }
    
    // Trade tokens
    function trade(uint256 amountInput, address inputToken, address outputToken) external {
        require(inputToken == address(token1) || inputToken == address(token2), "Invalid input token");
        require(outputToken == address(token1) || outputToken == address(token2), "Invalid output token");
        require(inputToken != outputToken, "Input and output tokens must be different");
        require(amountInput > 0, "Amount must be greater than zero");
        
        // Get pool balances
        uint256 balanceInputToken = IERC20(inputToken).balanceOf(address(this));
        uint256 balanceOutputToken = IERC20(outputToken).balanceOf(address(this));
        
        // Calculate output amount
        uint256 amountOutput = (amountInput * balanceOutputToken) / balanceInputToken;
        
        // Check liquidity
        require(amountOutput > 0, "Insufficient liquidity");
        
        // Transfer input tokens
        IERC20(inputToken).transferFrom(msg.sender, address(this), amountInput);
        // Transfer output tokens
        IERC20(outputToken).transfer(msg.sender, amountOutput);
        
        emit Trade(msg.sender, amountInput, amountOutput);
    }
    
    // Calculate the price of token1 in terms of token2 for a specific pool
    function getTokenPrice(address token1Address, address token2Address) onlyOwner external view returns (uint256) {
        require(totalLiquidity > 0, "No liquidity in the pool");
        require(token1Address != token2Address, "Tokens must be different");
        
        // Define tokens
        IERC20 token1 = IERC20(token1Address);
        IERC20 token2 = IERC20(token2Address);
        
        // Check pool balances
        uint256 balanceToken1 = IERC20(token1).balanceOf(address(this));
        uint256 balanceToken2 = IERC20(token2).balanceOf(address(this));
        
        // Calculate the price of token1 in terms of token2
        // Price = (balanceToken2 * 1e18) / balanceToken1, where 1e18 is the precision (18 decimal places)
        return (balanceToken2 * 1e18) / balanceToken1;
    }
    
    
    // Calculates the amount of tokens you will get if you withdraw liquidity
    function getLiquidity(address user) external view returns (uint256 token1Amount, uint256 token2Amount) {
        uint256 amountLP = liquidity[user];
        require(amountLP > 0, "User has no LP tokens");
        
        // Check pool balances
        uint256 balanceToken1 = IERC20(token1).balanceOf(address(this));
        uint256 balanceToken2 = IERC20(token2).balanceOf(address(this));
        
        // Calculate the proportions of each asset to withdraw
        token1Amount = (amountLP * balanceToken1) / totalLiquidity;
        token2Amount = (amountLP * balanceToken2) / totalLiquidity;
        
        return (token1Amount, token2Amount);
    }
    
    // Get the amount of LP tokens held by a user
    function getUserLPBalance(address user) external view returns (uint256) {
        return liquidity[user];
    }

}
