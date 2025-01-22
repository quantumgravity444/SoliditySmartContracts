pragma solidity ^0.8.0;

import "./Utils.sol";

contract OptimisticRollup {

    struct State {
        bytes32 root;
        uint256 timestamp;
        bool challenged;
        bool valid;
    }

    State[] public states;
    uint256 public challengePeriod;

    mapping(address => uint256) public balances;

    event StateSubmitted(uint256 indexed stateIndex, bytes32 root);
    event Deposit(address indexed user, uint256 amount);
    event Withdrawal(address indexed user, uint256 amount);
    event StateChallenged(uint256 indexed stateIndex);
    event ChallengeResolved(uint256 indexed stateIndex, bool fraud);

    constructor(uint256 _challengePeriod) {
        challengePeriod = _challengePeriod;
    }

    function processTransaction(uint256 stateIndex, bytes calldata transaction) external { require(stateIndex < states.length, "Invalid state index"); 
        State storage state = states[stateIndex]; 

        // Ensure that the state has not been challenged or invalidated 
        require(!state.challenged && state.valid, "State cannot be updated"); 

        // Update state root using the transaction data 
        state.root = Utils.updateStateRoot(state.root, transaction); 

        state.timestamp = block.timestamp; 
    }

    function submitState(bytes32 _root) external {
        states.push(State({
            root: _root,
            timestamp: block.timestamp,
            challenged: false,
            valid: true
        }));

        emit StateSubmitted(states.length - 1, _root);
    }

    function getState(uint256 stateIndex) view returns (bytes32 root, uint256 timestamp, bool challenged, bool valid) {
        require(stateIndex < states.length, "Invalid state index");
        State storage state = states[stateIndex];

        return (state.root, state.timestamp, state.challenged, state.valid);
    }

    function markStateChallenged(uint256 stateIndex) {
        require(stateIndex < states.length, "Invalid state index");
        State storage state = states[stateIndex];
        state.challenged = true;
    }

    function clearStateChallenge(uint256 stateIndex) {
        require(stateIndex < states.length, "Invalid state index");
        State storage state = states[stateIndex];
        state.challenged = false;
    }

    function invalidateState(uint256 stateIndex) {
        require(stateIndex < states.length, "Invalid state index");
        State storage state = states[stateIndex];
        state.valid = false;
    }

    function verifyState(uint256 stateIndex, bytes32[] calldata proof, bytes32 leaf) view returns (bool) { 
        require(stateIndex < states.length, "Invalid state index"); 
        State storage state = states[stateIndex]; 

        return Utils.verifyMerkleProof(proof, state.root, leaf); 
    }

    function challengeState(uint256 stateIndex) external {
        (,,bool challenged,) = getState(stateIndex);
        require(!challenged, "State already challenged");
        
        markStateChallenged(stateIndex);
        emit StateChallenged(stateIndex);
    }

    function resolveChallenge(uint256 stateIndex, bool fraud, bytes32[] calldata proof, bytes32 leaf) external {
        require(verifyState(stateIndex, proof, leaf), "Invalid proof");

        if (fraud) {
            invalidateState(stateIndex);
        } else {
            clearStateChallenge(stateIndex);
        }

        emit ChallengeResolved(stateIndex, fraud);
    }

    function deposit() external payable {
        balances[msg.sender] += msg.value;
        emit Deposit(msg.sender, msg.value);
    }

    function withdraw(uint256 amount) external {
        require(balances[msg.sender] >= amount, "Insufficient balance");
        balances[msg.sender] -= amount;
        payable(msg.sender).transfer(amount);
        emit Withdrawal(msg.sender, amount);
    }
}


pragma solidity ^0.8.0;

library Utils {

    struct Account {
        address addr;
        uint256 balance;
    }

    function updateAccountState(address account, uint256 newBalance) internal pure returns (bytes32 newLeaf) {
        // The new leaf is a hash of the updated account details
        newLeaf = keccak256(abi.encode(account, newBalance));
    }

    function decodeTransaction(bytes memory transaction) internal pure returns (address sender, address recipient, uint256 amount) {
        (sender, recipient, amount) = abi.decode(transaction, (address, address, uint256));
    }


    function updateStateRoot(
        bytes32 currentRoot,
        bytes memory transaction,
        bytes32[] memory proofSender,
        bytes32[] memory proofRecipient,
        uint256 senderInitialBalance,
        uint256 recipientInitialBalance
    ) internal pure returns (bytes32 newRoot) {
        // Decode the transaction into its components
        (address sender, address recipient, uint256 amount) = decodeTransaction(transaction);

        // Generate initial leaf hashes for sender and recipient
        bytes32 senderLeaf = keccak256(abi.encode(sender, senderInitialBalance));
        bytes32 recipientLeaf = keccak256(abi.encode(recipient, recipientInitialBalance));

        // Verify Merkle proofs for both sender and recipient
        require(verifyMerkleProof(proofSender, currentRoot, senderLeaf), "Invalid Merkle proof for sender");
        require(verifyMerkleProof(proofRecipient, currentRoot, recipientLeaf), "Invalid Merkle proof for recipient");

        // Ensure the sender has enough balance for the transaction
        require(senderInitialBalance >= amount, "Insufficient balance");

        // Update the balances of the sender and recipient
        uint256 newSenderBalance = senderInitialBalance - amount;
        uint256 newRecipientBalance = recipientInitialBalance + amount;

        // Encode the updated accounts back to leaf hashes
        bytes32 newSenderLeaf = updateAccountState(sender, newSenderBalance);
        bytes32 newRecipientLeaf = updateAccountState(recipient, newRecipientBalance);

        // Compute the new Merkle root with the updated leaves
        bytes32[] memory updatedLeaves;
        updatedLeaves[0] = newSenderLeaf;
        updatedLeaves[1] = newRecipientLeaf;
        newRoot = computeMerkleRoot(updatedLeaves);

        return newRoot;
    }

    // Utility function to verify a Merkle proof
    function verifyMerkleProof(bytes32[] memory proof, bytes32 root, bytes32 leaf) internal pure returns (bool) {

        bytes32 computedHash = leaf;

        for (uint256 i = 0; i < proof.length; i++) {
            bytes32 proofElement = proof[i];

            if (computedHash <= proofElement) {
                // Hash current leaf and current element of the proof
                computedHash = keccak256(abi.encodePacked(computedHash, proofElement));
            } else {
                // Hash current element of the proof and current leaf
                computedHash = keccak256(abi.encodePacked(proofElement, computedHash));
            }
        }

        // Check if the computed hash (root) is equal to the provided root
        return computedHash == root;
    }

    // Utility function to compute the Merkle root from a set of leaves
    function computeMerkleRoot(bytes32[] memory leaves) internal pure returns (bytes32) {

        require(leaves.length > 0, "Leaves cannot be empty");

        while (leaves.length > 1) {
            if (leaves.length % 2 != 0) {
                // If odd number of leaves, duplicate the last leaf
                leaves.push(leaves[leaves.length - 1]);
            }

            bytes32[] memory newLeaves = new bytes32[](leaves.length / 2);

            for (uint256 i = 0; i < leaves.length; i += 2) {
                newLeaves[i / 2] = keccak256(abi.encodePacked(leaves[i], leaves[i + 1]));
            }

            leaves = newLeaves;
        }

        return leaves[0];
    }


}
