// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

import "./SafeMath.sol";

contract GovernorPlasma {
    /// @notice The name of this contract
    string public constant name = "Governor Plasma";

    /// @notice The number of votes in support of a proposal required in order for a quorum to be reached and for a vote to succeed
    function quorumVotes() public pure returns (uint256) { return 40_000_000e18; } // 4% of PPAY

    /// @notice The number of votes required in order for a voter to become a proposer
    function proposalThreshold() public pure returns (uint256) { return 10_000_000e18; } // 1% of PPAY

    /// @notice The maximum number of actions that can be included in a proposal
    function proposalMaxOperations() public pure returns (uint256) { return 10; } // 10 actions

    /// @notice The delay before voting on a proposal may take place, once proposed
    function votingDelay() public pure returns (uint256) { return 1; } // 1 block

    /// @notice The duration of voting on a proposal, in blocks
    function votingPeriod() public pure returns (uint256) { return 40_320; } // ~7 days in blocks (assuming 15s blocks)

    /// @notice The address of the Plasma Protocol Timelock
    TimelockInterface public timelock;

    /// @notice The address of the Plasma governance token
    PpayInterface public ppay;

    /// @notice The total number of proposals
    uint256 public proposalCount;

    struct Proposal {
        //  Unique id for looking up a proposal
        uint256 id;

        //  Creator of the proposal
        address proposer;

        //  The timestamp that the proposal will be available for execution, set once the vote succeeds
        uint256 eta;

        //  The ordered list of target addresses for calls to be made
        address[] targets;

        //  The ordered list of values (i.e. msg.value) to be passed to the calls to be made
        uint256[] values;

        //  The ordered list of function signatures to be called
        string[] signatures;

        //  The ordered list of calldata to be passed to each call
        bytes[] calldatas;

        //  The block at which voting begins: holders must delegate their votes prior to this block
        uint256 startBlock;

        //  The block at which voting ends: votes must be cast prior to this block
        uint256 endBlock;

        //  Current number of votes in favor of this proposal
        uint256 forVotes;

        //  Current number of votes in opposition to this proposal
        uint256 againstVotes;

        //  Flag marking whether the proposal has been canceled
        bool canceled;

        //  Flag marking whether the proposal has been executed
        bool executed;

        //  Receipts of ballots for the entire set of voters
        mapping (address => Receipt) receipts;
    }

    /// @notice Ballot receipt record for a voter
    struct Receipt {
        //  Hether or not a vote has been cast
        bool hasVoted;

        //  Whether or not the voter supports the proposal
        bool support;

        //  The number of votes the voter had, which were cast
        uint96 votes;
    }

    /// @notice Possible states that a proposal may be in
    enum ProposalState {
        Pending,
        Active,
        Canceled,
        Defeated,
        Succeeded,
        Queued,
        Expired,
        Executed
    }

    /// @notice The official record of all proposals ever proposed
    mapping (uint256 => Proposal) public proposals;

    /// @notice The latest proposal for each proposer
    mapping (address => uint256) public latestProposalIds;

    /// @notice The EIP-712 typehash for the contract's domain
    bytes32 public constant DOMAIN_TYPEHASH = keccak256("EIP712Domain(string name,uint256 chainId,address verifyingContract)");

    /// @notice The EIP-712 typehash for the ballot struct used by the contract
    bytes32 public constant BALLOT_TYPEHASH = keccak256("Ballot(uint256 proposalId,bool support)");

    using SafeMath for uint256;

    /// @notice An event emitted when a new proposal is created
    event ProposalCreated(uint256 id, address proposer, address[] targets, uint256[] values, string[] signatures, bytes[] calldatas, uint256 startBlock, uint256 endBlock, string description);

    /// @notice An event emitted when a vote has been cast on a proposal
    event VoteCast(address voter, uint256 proposalId, bool support, uint256 votes);

    /// @notice An event emitted when a proposal has been canceled
    event ProposalCanceled(uint256 id);

    /// @notice An event emitted when a proposal has been queued in the Timelock
    event ProposalQueued(uint256 id, uint256 eta);

    /// @notice An event emitted when a proposal has been executed in the Timelock
    event ProposalExecuted(uint256 id);

    constructor(address timelock_, address ppay_) public {
        timelock = TimelockInterface(timelock_);
        ppay = PpayInterface(ppay_);
    }

    function propose(address[] memory targets, uint256[] memory values, string[] memory signatures, bytes[] memory calldatas, string memory description) external returns (uint256) {
        require(ppay.getPriorVotes(msg.sender, block.number.sub(1)) > proposalThreshold(), "GovernorPlasma::propose: proposer votes below proposal threshold");
        require(targets.length == values.length && targets.length == signatures.length && targets.length == calldatas.length, "GovernorPlasma::propose: proposal function information arity mismatch");
        require(targets.length != 0, "GovernorPlasma::propose: must provide actions");
        require(targets.length <= proposalMaxOperations(), "GovernorPlasma::propose: too many actions");

        uint256 latestProposalId = latestProposalIds[msg.sender];
        if (latestProposalId != 0) {
          ProposalState proposersLatestProposalState = state(latestProposalId);
          require(proposersLatestProposalState != ProposalState.Active, "GovernorPlasma::propose: one live proposal per proposer, found an already active proposal");
          require(proposersLatestProposalState != ProposalState.Pending, "GovernorPlasma::propose: one live proposal per proposer, found an already pending proposal");
        }

        uint256 startBlock = block.number.add(votingDelay());
        uint256 endBlock = startBlock.add(votingPeriod());

        proposalCount++;
        Proposal memory newProposal = Proposal({
            id: proposalCount,
            proposer: msg.sender,
            eta: 0,
            targets: targets,
            values: values,
            signatures: signatures,
            calldatas: calldatas,
            startBlock: startBlock,
            endBlock: endBlock,
            forVotes: 0,
            againstVotes: 0,
            canceled: false,
            executed: false
        });

        proposals[newProposal.id] = newProposal;
        latestProposalIds[newProposal.proposer] = newProposal.id;

        emit ProposalCreated(newProposal.id, msg.sender, targets, values, signatures, calldatas, startBlock, endBlock, description);
        return newProposal.id;
    }

    function queue(uint256 proposalId) external {
        require(state(proposalId) == ProposalState.Succeeded, "GovernorPlasma::queue: proposal can only be queued if it is succeeded");
        Proposal storage proposal = proposals[proposalId];
        uint256 eta = block.timestamp.add(timelock.delay());
        uint256 targetsLength = proposal.targets.length; 
        for (uint256 i = 0; i < targetsLength; i++) {
            _queueOrRevert(proposal.targets[i], proposal.values[i], proposal.signatures[i], proposal.calldatas[i], eta);
        }
        proposal.eta = eta;
        emit ProposalQueued(proposalId, eta);
    }

    function _queueOrRevert(address target, uint256 value, string memory signature, bytes memory data, uint256 eta) internal {
        require(!timelock.queuedTransactions(keccak256(abi.encode(target, value, signature, data, eta))), "GovernorPlasma::_queueOrRevert: proposal action already queued at eta");
        timelock.queueTransaction(target, value, signature, data, eta);
    }

    function execute(uint256 proposalId) external payable {
        require(state(proposalId) == ProposalState.Queued, "GovernorPlasma::execute: proposal can only be executed if it is queued");
        Proposal storage proposal = proposals[proposalId];
        proposal.executed = true;
        uint256 targetsLength = proposal.targets.length; 
        for (uint256 i = 0; i < targetsLength; i++) {
            timelock.executeTransaction{value: proposal.values[i]}(proposal.targets[i], proposal.values[i], proposal.signatures[i], proposal.calldatas[i], proposal.eta);
        }
        emit ProposalExecuted(proposalId);
    }

    function cancel(uint256 proposalId) external {
        ProposalState state = state(proposalId);
        require(state != ProposalState.Executed, "GovernorPlasma::cancel: cannot cancel executed proposal");

        Proposal storage proposal = proposals[proposalId];
        require(ppay.getPriorVotes(proposal.proposer, block.number.sub(1)) < proposalThreshold(), "GovernorPlasma::cancel: proposer above threshold");

        proposal.canceled = true;
        uint256 targetsLength = proposal.targets.length; 
        for (uint256 i = 0; i < targetsLength; i++) {
            timelock.cancelTransaction(proposal.targets[i], proposal.values[i], proposal.signatures[i], proposal.calldatas[i], proposal.eta);
        }

        emit ProposalCanceled(proposalId);
    }

    function getActions(uint256 proposalId) external view returns (address[] memory targets, uint256[] memory values, string[] memory signatures, bytes[] memory calldatas) {
        Proposal storage p = proposals[proposalId];
        return (p.targets, p.values, p.signatures, p.calldatas);
    }

    function getReceipt(uint256 proposalId, address voter) external view returns (Receipt memory) {
        return proposals[proposalId].receipts[voter];
    }

    function state(uint256 proposalId) public view returns (ProposalState) {
        require(proposalCount >= proposalId && proposalId > 0, "GovernorPlasma::state: invalid proposal id");
        Proposal storage proposal = proposals[proposalId];
        if (proposal.canceled) {
            return ProposalState.Canceled;
        } else if (block.number <= proposal.startBlock) {
            return ProposalState.Pending;
        } else if (block.number <= proposal.endBlock) {
            return ProposalState.Active;
        } else if (proposal.forVotes <= proposal.againstVotes || proposal.forVotes < quorumVotes()) {
            return ProposalState.Defeated;
        } else if (proposal.eta == 0) {
            return ProposalState.Succeeded;
        } else if (proposal.executed) {
            return ProposalState.Executed;
        } else if (block.timestamp >= proposal.eta.add(timelock.GRACE_PERIOD())) {
            return ProposalState.Expired;
        } else {
            return ProposalState.Queued;
        }
    }

    function castVote(uint256 proposalId, bool support) external {
        return _castVote(msg.sender, proposalId, support);
    }

    function castVoteBySig(uint256 proposalId, bool support, uint8 v, bytes32 r, bytes32 s) external {
        bytes32 domainSeparator = keccak256(abi.encode(DOMAIN_TYPEHASH, keccak256(bytes(name)), getChainId(), address(this)));
        bytes32 structHash = keccak256(abi.encode(BALLOT_TYPEHASH, proposalId, support));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        address signatory = ecrecover(digest, v, r, s);
        require(signatory != address(0), "GovernorPlasma::castVoteBySig: invalid signature");
        return _castVote(signatory, proposalId, support);
    }

    function _castVote(address voter, uint256 proposalId, bool support) internal {
        require(state(proposalId) == ProposalState.Active, "GovernorPlasma::_castVote: voting is closed");
        Proposal storage proposal = proposals[proposalId];
        Receipt storage receipt = proposal.receipts[voter];
        require(receipt.hasVoted == false, "GovernorPlasma::_castVote: voter already voted");
        uint96 votes = ppay.getPriorVotes(voter, proposal.startBlock);

        if (support) {
            proposal.forVotes = proposal.forVotes.add(votes);
        } else {
            proposal.againstVotes = proposal.againstVotes.add(votes);
        }

        receipt.hasVoted = true;
        receipt.support = support;
        receipt.votes = votes;

        emit VoteCast(voter, proposalId, support, votes);
    }

    function getChainId() internal pure returns (uint256) {
        uint256 chainId;
        assembly { chainId := chainid() }
        return chainId;
    }
}

interface TimelockInterface {
    function delay() external view returns (uint256);
    function GRACE_PERIOD() external view returns (uint256);
    function acceptAdmin() external;
    function queuedTransactions(bytes32 hash) external view returns (bool);
    function queueTransaction(address target, uint256 value, string calldata signature, bytes calldata data, uint256 eta) external returns (bytes32);
    function cancelTransaction(address target, uint256 value, string calldata signature, bytes calldata data, uint256 eta) external;
    function executeTransaction(address target, uint256 value, string calldata signature, bytes calldata data, uint256 eta) external payable returns (bytes memory);
}

interface PpayInterface {
    function getPriorVotes(address account, uint256 blockNumber) external view returns (uint96);
}