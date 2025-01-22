pragma solidity ^0.8.0;

contract StateChannel {

struct Channel {
        address payable participant1;
        address payable participant2;
        uint256 balance1;
        uint256 balance2;
        uint256 nonce;
        bool exists;
        uint256 closingTime;
        bool isClosing;
    }

mapping(bytes32 => Channel) public channels;

event ChannelOpened(bytes32 indexed channelId, address participant1, address participant2);
event ChannelFunded(bytes32 indexed channelId, address participant, uint256 amount);
event ChannelStateUpdated(bytes32 indexed channelId, uint256 balance1, uint256 balance2, uint256 nonce);
event ChannelClosingInitiated(bytes32 indexed channelId);
event ChannelClosed(bytes32 indexed channelId, address participant1, address participant2, uint256 balance1, uint256 balance2);

uint256 public constant DISPUTE_PERIOD = 1 days;

constructor() {
    owner = msg.sender;
}

modifier onlyOwner() {
    require(msg.sender == owner, "Caller is not the owner");
    _;
}

function openChannel(address payable _participant2) external payable returns (bytes32) {

    require(msg.value > 0, "Initial funding required");

    bytes32 channelId = keccak256(abi.encodePacked(msg.sender, _participant2, block.timestamp));
    require(!channels[channelId].exists, "Channel already exists");

    channels[channelId] = Channel({
                participant1: payable(msg.sender),
                participant2: _participant2,
                balance1: msg.value,
                balance2: 0,
                nonce: 0,
                exists: true,
                closingTime: 0,
                isClosing: false
            });

    emit ChannelOpened(channelId, msg.sender, _participant2);
    return channelId;
}

function fundChannel(bytes32 _channelId) external payable {

    Channel storage channel = channels[_channelId];
    require(channel.exists, "Channel does not exist");
    require(msg.sender == channel.participant1 || msg.sender == channel.participant2, "Not a participant");

    if (msg.sender == channel.participant1) {
            channel.balance1 += msg.value;
        } else {
            channel.balance2 += msg.value;
        }

    emit ChannelFunded(_channelId, msg.sender, msg.value)
}

function updateState(bytes32 _channelId, uint256 _balance1, uint256 _balance2, uint256 _nonce, bytes memory _signature1, bytes memory _signature2) public {

    Channel storage channel = channels[_channelId];
    require(channel.exists, "Channel does not exist");
    require(_nonce > channel.nonce, "Invalid nonce");

    bytes32 message = prefixed(keccak256(abi.encodePacked(_channelId, _balance1, _balance2, _nonce)));
    require(recoverSigner(message, _signature1) == channel.participant1, "Invalid signature from participant1");
    require(recoverSigner(message, _signature2) == channel.participant2, "Invalid signature from participant2");

    channel.balance1 = _balance1;
    channel.balance2 = _balance2;
    channel.nonce = _nonce;

    emit ChannelStateUpdated(_channelId, _balance1, _balance2, _nonce);
}

function initiateCloseChannel(bytes32 _channelId) external {

    Channel storage channel = channels[_channelId];
    require(channel.exists, "Channel does not exist");
    require(msg.sender == channel.participant1 || msg.sender == channel.participant2, "Not a participant");

    channel.isClosing = true;
    channel.closingTime = block.timestamp + DISPUTE_PERIOD;

    emit ChannelClosingInitiated(_channelId);
}

function closeChannel(bytes32 _channelId, uint256 _balance1, uint256 _balance2, uint256 _nonce, bytes memory _signature1, bytes memory _signature2) public {

    Channel storage channel = channels[_channelId];
    require(channel.exists, "Channel does not exist");
    require(channel.isClosing, "Channel is not closing");
    require(block.timestamp >= channel.closingTime, "Dispute period has not ended");

    uint256 totalBalance = channel.balance1 + channel.balance2;
    require(_balance1 + _balance2 == totalBalance, "New balances do not match the total balance");

    updateState(_channelId, _balance1, _balance2, _nonce, _signature1, _signature2);

    channel.participant1.transfer(channel.balance1);
    channel.participant2.transfer(channel.balance2);

    emit ChannelClosed(_channelId, channel.participant1, channel.participant2, channel.balance1, channel.balance2);

    delete channels[_channelId];
}

function forceCloseChannel(bytes32 _channelId, uint256 _balance1, uint256 _balance2, uint256 _nonce, bytes memory _signature1, bytes memory _signature2) onlyOwner external {

    Channel storage channel = channels[_channelId];
    require(channel.exists, "Channel does not exist");

    uint256 totalBalance = channel.balance1 + channel.balance2; 
    require(_balance1 + _balance2 == totalBalance, "New balances do not match the total balance");

    updateState(_channelId, _balance1, _balance2, _nonce, _signature1, _signature2);

    channel.participant1.transfer(channel.balance1);
    channel.participant2.transfer(channel.balance2);

    emit ChannelClosed(_channelId, channel.participant1, channel.participant2, channel.balance1, channel.balance2);

    delete channels[_channelId];
}

function prefixed(bytes32 hash) internal pure returns (bytes32) {

    return keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", hash));
}

function recoverSigner(bytes32 message, bytes memory sig) internal pure returns (address) {

    uint8 v;
    bytes32 r;
    bytes32 s;

    (v, r, s) = splitSignature(sig);
    return ecrecover(message, v, r, s);
}

function splitSignature(bytes memory sig) internal pure returns (uint8, bytes32, bytes32) {

    require(sig.length == 65, "Invalid signature length");

    bytes32 r;
    bytes32 s;
    uint8 v;

    assembly {
        r := mload(add(sig, 32))
        s := mload(add(sig, 64))
        v := byte(0, mload(add(sig, 96)))
    }

    return (v, r, s);
}

}



const Web3 = require('web3');
const web3 = new Web3('https://mainnet.infura.io/v3/YOUR_INFURA_PROJECT_ID');


// Replace these with actual private keys and channel details
const privateKey1 = '0xPRIVATE_KEY_OF_PARTICIPANT1';
const privateKey2 = '0xPRIVATE_KEY_OF_PARTICIPANT2';
const channelId = '0xCHANNEL_ID'; // This should be the same ID as used in the contract
const balance1 = web3.utils.toWei('1', 'ether'); // New balance for participant1
const balance2 = web3.utils.toWei('1', 'ether'); // New balance for participant2
const nonce = 1; // New nonce for the state update

// Create the message to be signed
const message = web3.utils.soliditySha3(
  { type: 'bytes32', value: channelId },
  { type: 'uint256', value: balance1 },
  { type: 'uint256', value: balance2 },
  { type: 'uint256', value: nonce }
);

console.log(`Message: ${message}`);

// Sign the message with both participants' private keys
const signature1 = web3.eth.accounts.sign(message, privateKey1).signature;
const signature2 = web3.eth.accounts.sign(message, privateKey2).signature;

console.log(`Signature 1: ${signature1}`);
console.log(`Signature 2: ${signature2}`);
