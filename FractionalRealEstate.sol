pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

// Fractional Real Estate Protocol
contract FractionalRealEstate is Ownable, ERC20, AggregatorV3Interface {
    
    // Stores assets on the blockchain
    struct Asset {
        address owner;
        string description;
        uint256 totalShares;
        uint256 pricePerShare;
    }
    
    // Stores orders on the blockchain
    struct Order {
        address orderOwner;
        uint256 assetId;
        uint256 shareCount;
    }
    
    mapping(uint256 => Asset) public assets;
    mapping(uint256 => Order[]) public buyOrders;
    mapping(uint256 => Order[]) public sellOrders;
    uint256 public assetCount;

    ERC20 public token;
    address public owner;
    AggregatorV3Interface internal priceFeed; // Chainlink price feed contract
    
    // Events
    event RegisterAsset(string description, uint256 price, uint256 shares);
    event SetAssetPrice(uint256 assetId, uint256 newPrice);
    event PlaceBuyOrder(uint256 assetId, uint256 shareCount);
    event PlaceSellOrder(uint256 assetId, uint256 shareCount);
    event ExecuteBuyOrder(uint256 assetId, uint256 orderIndex);
    event ExecuteSellOrder(uint256 assetId, uint256 orderIndex, uint256 shareCount, uint256 sellPrice);
    event ExecuteBuyOrderWithToken(uint256 assetId, uint256 orderIndex, uint256 tokenAmount);
    event ExecuteSellOrderWithToken(uint256 assetId, uint256 orderIndex, uint256 shareCount, uint256 sellPrice, uint256 tokenAmount);

    // Constructor
    constructor(address _tokenAddress, address _priceFeed) {
        token = ERC20(_tokenAddress);
        owner = msg.sender;
        priceFeed = AggregatorV3Interface(_priceFeed);
    }
    
    function registerAsset(string memory description, uint256 price, uint256 shares) external onlyOwner {
        require(shares > 0, "Shares must be greater than 0.");
        assetCount++;
        assets[assetCount] = Asset(msg.sender, description, price, shares);
        
        emit RegisterAsset(description, price, shares);
    }
    
    function setAssetPrice(uint256 assetId, uint256 newPrice) external onlyOwner {
        require(assetId > 0 && assetId <= assetCount, "Invalid asset ID.");
        Asset storage asset = assets[assetId];
        require(asset.owner != address(0), "Asset does not exist.");
        asset.price = newPrice;
        
        emit SetAssetPrice(assetId, newPrice);
    }
    
    function editAssetDescription(uint256 assetId, string memory newDescription) external onlyOwner {
        require(assetId > 0 && assetId <= assetCount, "Invalid asset ID.");
        require(assets[assetId].owner == msg.sender, "Only asset owner can edit the description.");

        assets[assetId].description = newDescription;
    }
    
    function changeShareCount(uint256 assetId, uint256 newShareCount) external onlyOwner {
        require(assetId > 0 && assetId <= assetCount, "Invalid asset ID.");
        require(assets[assetId].owner == msg.sender, "Only asset owner can change share count.");
        require(newShareCount > 0, "New share count must be greater than 0.");
        
        assets[assetId].totalShares = newShareCount;
    }
    
    function transferAssetOwnership(uint256 assetId, address newOwner) external onlyOwner {
        require(assetId > 0 && assetId <= assetCount, "Invalid asset ID.");
        require(newOwner != address(0), "Invalid new owner address.");
        require(assets[assetId].owner == msg.sender, "Only asset owner can transfer ownership.");
        
        assets[assetId].owner = newOwner;
    }
    
    function placeBuyOrder(uint256 assetId, uint256 shareCount) external {
        require(assetId > 0 && assetId <= assetCount, "Invalid asset ID.");
        require(assets[assetId].owner != address(0), "Asset does not exist.");
        require(shareCount > 0, "Share count must be greater than 0.");

        buyOrders[assetId].push(Order(msg.sender, assetId, shareCount));
        
        emit PlaceBuyOrder(assetId, shareCount);
    }
    
    function placeLimitBuyOrder(uint256 assetId, uint256 shareCount, uint256 pricePerShare) external {
        require(assetId > 0 && assetId <= assetCount, "Invalid asset ID.");
        require(assets[assetId].owner != address(0), "Asset does not exist.");
        require(shareCount > 0, "Share count must be greater than 0.");
        require(pricePerShare > 0, "Price per share must be greater than 0.");
        
        // Store the buy order in the buyOrders mapping
        buyOrders[assetId].push(Order(msg.sender, assetId, shareCount, pricePerShare));
        
        emit PlaceBuyOrder(assetId, shareCount, pricePerShare);
    }
    
    function placeSellOrder(uint256 assetId, uint256 shareCount) external {
        require(assetId > 0 && assetId <= assetCount, "Invalid asset ID.");
        require(assets[assetId].owner == msg.sender, "Only asset owner can place sell orders.");
        require(shareCount > 0, "Share count must be greater than 0.");

        sellOrders[assetId].push(Order(msg.sender, assetId, shareCount));
        
        emit PlaceSellOrder(assetId, shareCount);
     }
     
     function placeLimitSellOrder(uint256 assetId, uint256 shareCount, uint256 pricePerShare) external {
         require(assetId > 0 && assetId <= assetCount, "Invalid asset ID.");
         require(assets[assetId].owner == msg.sender, "Only asset owner can place limit sell orders.");
         require(shareCount > 0, "Share count must be greater than 0.");
         require(pricePerShare > 0, "Price per share must be greater than 0.");
         
         // Store the sell order in the sellOrders mapping
         sellOrders[assetId].push(Order(msg.sender, assetId, shareCount, pricePerShare));
         
         emit PlaceSellOrder(assetId, shareCount, pricePerShare);
     }
     
     function executeBuyOrder(uint256 assetId, uint256 orderIndex) external payable {
        require(assetId > 0 && assetId <= assetCount, "Invalid asset ID.");
        require(orderIndex < buyOrders[assetId].length, "Invalid order index.");

        Asset storage asset = assets[assetId];
        require(asset.owner != address(0), "Asset does not exist.");
        Order storage order = buyOrders[assetId][orderIndex];
        require(order.orderOwner != address(0), "Order does not exist.");
        require(order.shareCount > 0, "Order has been fulfilled.");

        uint256 ethPrice = getEthPrice();
        uint256 totalValue = (asset.pricePerShare * order.shareCount * ethPrice) / 1e18;
        require(msg.value >= totalValue, "Insufficient Ether value.");

        asset.shares -= order.shareCount;
        if (asset.shares == 0) {
            delete assets[assetId];
        }

        payable(asset.owner).transfer(totalValue);

        // Refund any excess Ether to the buyer
        if (msg.value > totalValue) {
            payable(order.buyer).transfer(msg.value - totalValue);
        }

        // Update the order status
        order.shareCount = 0;
         
        emit ExecuteBuyOrder(assetId, orderIndex);
    }
    
    function executeLimitBuyOrder(uint256 assetId, uint256 orderIndex) external payable {
        require(assetId > 0 && assetId <= assetCount, "Invalid asset ID.");
        require(orderIndex < buyOrders[assetId].length, "Invalid order index.");
        
        Asset storage asset = assets[assetId];
        require(asset.owner != address(0), "Asset does not exist.");
        Order storage order = buyOrders[assetId][orderIndex];
        require(order.orderOwner != address(0), "Order does not exist.");
        require(order.shareCount > 0, "Order has been fulfilled.");
        require(msg.value >= order.pricePerShare * order.shareCount, "Insufficient Ether value.");
        
        // Check if the asset price is lower or equal to the limit price set in the order
        require(asset.pricePerShare <= order.pricePerShare, "Asset price is higher than the limit price.");
        
        uint256 ethPrice = getEthPrice();
        uint256 totalValue = (order.pricePerShare * order.shareCount * ethPrice) / 1e18;
        
        // Subtract the bought shares from the asset's totalShares
        asset.totalShares -= order.shareCount;
        
        // Transfer the Ether from the buyer to the asset owner
        payable(asset.owner).transfer(totalValue);
        
        // Update the order status to mark it as fulfilled (share count set to 0)
        order.shareCount = 0;
        
        emit ExecuteBuyOrder(assetId, orderIndex);
    }
    
    function executeSellOrder(uint256 assetId, uint256 orderIndex, uint256 shareCount, uint256 sellPrice) external {
        require(assetId > 0 && assetId <= assetCount, "Invalid asset ID.");
        require(orderIndex < sellOrders[assetId].length, "Invalid order index.");

        Asset storage asset = assets[assetId];
        require(asset.owner != address(0), "Asset does not exist.");
        Order storage order = buyOrders[assetId][orderIndex];
        require(order.orderOwner != address(0), "Order does not exist.");
        require(order.shareCount > 0, "Order has been fulfilled.");
        require(order.shareCount >= shareCount, "Not enough shares in the order.");

        uint256 ethPrice = getEthPrice();
        uint256 totalValue = (sellPrice * shareCount * ethPrice) / 1e18;
        require(totalValue > 0, "Invalid sell price.");

        asset.shares += shareCount;
        payable(order.orderOwner).transfer(totalValue);

        // Refund any remaining shares to the seller
        if (order.shareCount > shareCount) {
            uint256 remainingShares = order.shareCount - shareCount;
            asset.shares -= remainingShares;
            payable(msg.sender).transfer(sellPrice * remainingShares);
        }

        // Update the order status
        order.shareCount -= shareCount;
        
        emit ExecuteSellOrder(assetId, orderIndex, shareCount, sellPrice);
    }
    
    function executeLimitSellOrder(uint256 assetId, uint256 orderIndex, uint256 shareCount) external {
        require(assetId > 0 && assetId <= assetCount, "Invalid asset ID.");
        require(orderIndex < sellOrders[assetId].length, "Invalid order index.");
        
        Asset storage asset = assets[assetId];
        require(asset.owner != address(0), "Asset does not exist.");
        
        Order storage order = sellOrders[assetId][orderIndex];
        require(order.orderOwner != address(0), "Order does not exist.");
        require(order.shareCount > 0, "Order has been fulfilled.");
        require(order.shareCount >= shareCount, "Not enough shares in the order.");
        
        // Check if the asset price is higher or equal to the limit price set in the order
        require(asset.pricePerShare >= order.pricePerShare, "Asset price is lower than the limit price.");
        
        uint256 ethPrice = getEthPrice();
        uint256 totalValue = (order.pricePerShare * shareCount * ethPrice) / 1e18;
        require(totalValue > 0, "Invalid sell price.");
        
        // Refund any remaining shares to the seller
        if (order.shareCount > shareCount) {
            uint256 remainingShares = order.shareCount - shareCount;
            asset.totalShares -= remainingShares;
        }
        
        // Update the order status to reflect the sold shares
        order.shareCount -= shareCount;
        
        emit ExecuteSellOrder(assetId, orderIndex, shareCount, order.pricePerShare);
    }
    
    // TODO: Add Chainlink integration
    function executeBuyOrderWithToken(uint256 assetId, uint256 orderIndex, uint256 tokenAmount) external {
        require(assetId > 0 && assetId <= assetCount, "Invalid asset ID.");
        require(orderIndex < buyOrders[assetId].length, "Invalid order index.");

        Asset storage asset = assets[assetId];
        require(asset.owner != address(0), "Asset does not exist.");
        Order storage order = buyOrders[assetId][orderIndex];
        require(order.orderOwner != address(0), "Order does not exist.");
        require(order.shareCount > 0, "Order has been fulfilled.");

        uint256 totalValue = asset.pricePerShare * order.shareCount;
        require(token.balanceOf(msg.sender) >= tokenAmount, "Insufficient token balance.");

        asset.totalShares -= order.shareCount;
        if (asset.totalShares == 0) {
            delete assets[assetId];
        }

        require(token.transferFrom(msg.sender, asset.owner, tokenAmount), "Token transfer failed.");

        // Refund any excess tokens to the buyer
        if (token.balanceOf(msg.sender) > tokenAmount) {
            uint256 excessTokens = token.balanceOf(msg.sender) - tokenAmount;
            require(token.transfer(msg.sender, excessTokens), "Token transfer failed.");
        }

        // Update the order status
        order.shareCount = 0;
        
        emit ExecuteBuyOrderWithToken(assetId, orderIndex, tokenAmount);
    }
    
    function executeLimitBuyOrderWithToken(uint256 assetId, uint256 orderIndex, uint256 tokenAmount) external {
        require(assetId > 0 && assetId <= assetCount, "Invalid asset ID.");
        require(orderIndex < buyOrders[assetId].length, "Invalid order index.");
        
        Asset storage asset = assets[assetId];
        require(asset.owner != address(0), "Asset does not exist.");
        Order storage order = buyOrders[assetId][orderIndex];
        require(order.orderOwner != address(0), "Order does not exist.");
        require(order.shareCount > 0, "Order has been fulfilled.");
        
        // Calculate the total token value required to fulfill the order
        uint256 totalValue = asset.pricePerShare * order.shareCount;
        
        // Check if the buyer has enough tokens to execute the buy order
        require(token.balanceOf(msg.sender) >= totalValue, "Insufficient token balance.");
        
        // Transfer tokens from the buyer to the order owner
        require(token.transferFrom(msg.sender, order.orderOwner, totalValue), "Token transfer failed.");
        
        // Update the order status to mark it as fulfilled (share count set to 0)
        order.shareCount = 0;
        
        emit ExecuteBuyOrderWithToken(assetId, orderIndex, totalValue);
    }
    
    // TODO: Add Chainlink integration
    function executeSellOrderWithToken(uint256 assetId, uint256 orderIndex, uint256 shareCount, uint256 sellPrice, uint256 tokenAmount) external {
        require(assetId > 0 && assetId <= assetCount, "Invalid asset ID.");
        require(orderIndex < sellOrders[assetId].length, "Invalid order index.");

        Asset storage asset = assets[assetId];
        require(asset.owner != address(0), "Asset does not exist.");
        Order storage order = sellOrders[assetId][orderIndex];
        require(order.orderOwner != address(0), "Order does not exist.");
        require(order.shareCount > 0, "Order has been fulfilled.");
        require(order.shareCount >= shareCount, "Not enough shares in the order.");

        uint256 totalValue = sellPrice * shareCount;
        require(token.balanceOf(msg.sender) >= tokenAmount, "Insufficient token balance.");

        asset.totalShares += shareCount;
        require(token.transferFrom(msg.sender, order.orderOwner, tokenAmount), "Token transfer failed.");

        // Refund any remaining shares to the seller
        if (order.shareCount > shareCount) {
            uint256 remainingShares = order.shareCount - shareCount;
            asset.totalShares -= remainingShares;
            require(token.transfer(msg.sender, sellPrice * remainingShares), "Token transfer failed.");
        }

        // Update the order status
        order.shareCount -= shareCount;
        
        emit event ExecuteSellOrderWithToken(assetId, orderIndex, shareCount, sellPrice, tokenAmount);
    }
    
    function executeLimitSellOrderWithToken(uint256 assetId, uint256 orderIndex, uint256 shareCount, uint256 tokenAmount) external {
        require(assetId > 0 && assetId <= assetCount, "Invalid asset ID.");
        require(orderIndex < sellOrders[assetId].length, "Invalid order index.");
        
        Asset storage asset = assets[assetId];
        require(asset.owner != address(0), "Asset does not exist.");
        Order storage order = sellOrders[assetId][orderIndex];
        require(order.orderOwner != address(0), "Order does not exist.");
        require(order.shareCount > 0, "Order has been fulfilled.");
        require(order.shareCount >= shareCount, "Not enough shares in the order.");
        
        // Calculate the total token value based on the share count and the order's price per share
        uint256 totalValue = order.pricePerShare * shareCount;
        
        // Check if the seller has enough tokens to cover the total token value
        require(token.balanceOf(msg.sender) >= totalValue, "Insufficient token balance.");
        
        // Add the sold shares back to the asset's totalShares
        asset.totalShares += shareCount;
        
        // Transfer tokens from the seller to the order owner
        require(token.transferFrom(msg.sender, order.orderOwner, totalValue), "Token transfer failed.");
        
        // Refund any remaining shares to the seller
        if (order.shareCount > shareCount) {
            uint256 remainingShares = order.shareCount - shareCount;
            asset.totalShares -= remainingShares;
        }
        
        // Update the order status to reflect the sold shares
        order.shareCount -= shareCount;
        
        emit ExecuteSellOrderWithToken(assetId, orderIndex, shareCount, order.pricePerShare, totalValue);
    }
    
    function getEthPrice() internal view returns (uint256) {
        (, int256 price, , , ) = priceFeed.latestRoundData();
        return uint256(price);
    }
    
    function withdrawEther() external onlyOwner {
        payable(owner).transfer(address(this).balance);
    }
    
    function withdrawTokens() external onlyowner {
        uint256 tokenBalance = token.balanceOf(address(this));
        token.transfer(owner, tokenBalance);
    }
    
    function changeTokenAddress(address newTokenAddress) external onlyOwner {
        require(newTokenAddress != address(0), "Invalid token address.");
        token = ERC20(newTokenAddress);
    }
    
    //Getter functions
    function getAssetCount() external view returns (uint256) {
        return assetCount;
    }
    
    function getAsset(uint256 assetId) public view returns (
        address owner,
        string memory description,
        uint256 totalShares,
        uint256 pricePerShare
    ) {
        Asset storage asset = assets[assetId];
        owner = asset.owner;
        description = asset.description;
        totalShares = asset.totalShares;
        pricePerShare = asset.pricePerShare;
    }
    
    function getAssetOwner(uint256 assetId) public view returns (address owner) {
        Asset storage asset = assets[assetId];
        owner = asset.owner;
    }
    
    function getAssetDescription(uint256 assetId) public view returns (string memory description) {
        Asset storage asset = assets[assetId];
        description = asset.description;
    }  
    
    function getAssetTotalShares(uint256 assetId) public view returns (uint256 totalShares) {
        Asset storage asset = assets[assetId];
        totalShares = asset.totalShares;
    }
    
    function getAssetPricePerShare(uint256 assetId) public view returns (uint256 pricePerShare) {
        Asset storage asset = assets[assetId];
        pricePerShare = asset.pricePerShare;
    }
    
    function getOrder(uint256 orderId) public view returns (
        address orderOwner,
        uint256 assetId,
        uint256 shareCount
    ) {
        Order storage order = orders[orderId];
        orderOwner = order.orderOwner;
        assetId = order.assetId;
        shareCount = order.shareCount;
    }
    
    function getOrderOwner(uint256 orderId) public view returns (address orderOwner) {
        Order storage order = orders[orderId];
        orderOwner = order.orderOwner;
    }
    
    function getOrderAssetId(uint256 orderId) public view returns (uint256 assetId) {
        Order storage order = orders[orderId];
        assetId = order.assetId;
    }
    
    function getOrderShareCount(uint256 orderId) public view returns (uint256 shareCount) {
        Order storage order = orders[orderId];
        shareCount = order.shareCount;
    }
}
