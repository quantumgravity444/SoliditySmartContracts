pragma solidity ^0.8.0;

contract ERC1155 {

    // Mapping from token ID to owner balances
    mapping(uint256 tokenId => mapping(address => uint256)) private _balances;

    // Mapping from token ID to total supply
    mapping(uint256 tokenId => uint256) private _totalSupply;

    // Mapping from token ID to token URI
    mapping(uint256 tokenId => string) private _tokenURIs;
    
    // Operator address of the contract
    address public owner;
    
    // Transfer events
    event TransferSingle(address indexed operator, address indexed from, address indexed to, uint256 tokenId, uint256 amount);
    event TransferBatch(address indexed operator, address indexed from, address indexed to, uint256[] tokenIds, uint256[] amounts);
    
     // Minting events
    event Mint(address indexed to, uint256 tokenId, uint256 amount);
    event MintBatch(address indexed to, uint256[] tokenIds, uint256[] amounts);
    
    // URI event
    event URI(string value, uint256 indexed tokenId);
    
    constructor() {
        owner = msg.sender;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Caller is not the owner");
        _;
    }

    // Get balance of an account's tokens
    function balanceOf(address account, uint256 tokenId) public view returns (uint256) {
        require(account != address(0), "ERC1155: balance query for the zero address");
        return _balances[tokenId][account];
    }

    // Get balances of multiple accounts/tokens
    function balanceOfBatch(address[] memory accounts, uint256[] memory tokenIds) public view returns (uint256[] memory) {
        require(accounts.length == tokenIds.length, "ERC1155: accounts and tokenIds length mismatch");

        uint256[] memory batchBalances = new uint256[](accounts.length);

        for (uint256 i = 0; i < accounts.length; i++) {
            batchBalances[i] = balanceOf(accounts[i], tokenIds[i]);
        }

        return batchBalances;
    }
    
    // Get total supply of a specific token ID
    function totalSupply(uint256 tokenId) public view returns (uint256) {
        return _totalSupply[tokenId];
    }
    
    // Get total supplies of multiple token IDs
    function totalSupplyBatch(uint256[] memory tokenIds) public view returns (uint256[] memory) {
        uint256[] memory batchTotalSupply = new uint256[](tokenIds.length);

        for (uint256 i = 0; i < tokenIds.length; i++) {
            batchTotalSupply[i] = totalSupply(tokenIds[i]);
        }

        return batchTotalSupply;
    }
    
    // Transfer tokens
    function transferFrom(address from, address to, uint256 tokenId, uint256 amount) public {
        require(from != address(0), "ERC1155: transfer from the zero address");
        require(to != address(0), "ERC1155: transfer to the zero address");
        require(_balances[tokenId][from] >= amount, "ERC1155: insufficient balance for transfer");

        _balances[tokenId][from] -= amount;
        _balances[tokenId][to] += amount;

        emit TransferSingle(msg.sender, from, to, tokenId, amount);
    }
    
    // Batch transfer tokens
    function transferFromBatch(address from, address to, uint256[] memory tokenIds, uint256[] memory amounts) public {
        require(from != address(0), "ERC1155: transfer from the zero address");
        require(to != address(0), "ERC1155: transfer to the zero address");
        require(tokenIds.length == amounts.length, "ERC1155: tokenIds and amounts length mismatch");

        for (uint256 i = 0; i < tokenIds.length; i++) {
            uint256 tokenId = tokenIds[i];
            uint256 amount = amounts[i];

            require(_balances[tokenId][from] >= amount, "ERC1155: insufficient balance for transfer");

            _balances[tokenId][from] -= amount;
            _balances[tokenId][to] += amount;
        }

        emit TransferBatch(msg.sender, from, to, tokenIds, amounts);
    }
    
     // Mint new tokens with a URI
    function mint(address to, uint256 tokenId, uint256 amount, string memory uri_) onlyOwner public {
        require(to != address(0), "ERC1155: mint to the zero address");

        _balances[tokenId][to] += amount;
        _totalSupply[tokenId] += amount;
        
        _setURI(tokenId, uri_);

        emit Mint(to, tokenId, amount);
    }
    
    // Batch mint new tokens with URIs
    function mintBatch(address to, uint256[] memory tokenIds, uint256[] memory amounts, string[] memory uris) onlyOwner public {
        require(to != address(0), "ERC1155: mint to the zero address");
        require(tokenIds.length == amounts.length && tokenIds.length == uris.length, "ERC1155: tokenIds, amounts, and uris length mismatch");

        for (uint256 i = 0; i < tokenIds.length; i++) {
            uint256 tokenId = tokenIds[i];
            uint256 amount = amounts[i];
            string memory uri_ = uris[i];

            _balances[tokenId][to] += amount;
            _totalSupply[tokenId] += amount;
            
            _setURI(tokenId, uri_);
        }

        emit MintBatch(to, tokenIds, amounts);
    }
    
    // Set URI for a token ID
    function _setURI(uint256 tokenId, string memory uri_) internal {
        _tokenURIs[tokenId] = uri_;
        emit URI(uri_, tokenId);
    }
    
    // Get URI for a token ID
    function uri(uint256 tokenId) public view returns (string memory) {
        return _tokenURIs[tokenId];
    }
}
