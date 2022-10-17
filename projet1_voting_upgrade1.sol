// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

import "https://github.com/OpenZeppelin/openzeppelin-contracts/contracts/access/Ownable.sol";

contract Voting is Ownable {
    // VARIABLES
    uint256 winningProposalId;

    enum WorkflowStatus {
        RegisteringVoters, //0
        ProposalsRegistrationStarted, //1
        ProposalsRegistrationEnded, //2
        VotingSessionStarted, //3
        VotingSessionEnded, //4
        VotesTallied //5
    }

    WorkflowStatus currentWorkflowStatus;

    struct Voter {
        bool isRegistered;
        bool hasVoted;
        uint256 votedProposalId;
    }

    struct Proposal {
        string description;
        uint256 voteCount;
    }

    mapping(address => Voter) voterMapping; // mapping pour stocker les address des voters

    Proposal[] proposals; // array pour stocker les propositions faites

    address[] votersAddress; // tableau pour stocker une liste finie des address des votant pour permettre la réinitialisation en cas vote égaux

    event VoterRegistered(address voterAddress);
    event WorkflowStatusChange(
        WorkflowStatus previousStatus,
        WorkflowStatus newStatus
    );
    event ProposalRegistered(uint256 proposalId);
    event Voted(address voter, uint256 proposalId);

    // MOFIFIERS
    modifier isVoterRegistered() {
        require(
            voterMapping[msg.sender].isRegistered,
            "you're not registered to this voting session"
        );
        _;
    }

    // FUNCTIONS

    // FONCTIONS DE MODIFICATION DU STATUS DU WORKFLOW -----
    /** fonction permettant de passer au status de workflow suivant (le workflow étant équentiel) */
    function _nextStep()
        public
        onlyOwner
        returns (string memory processStatus)
    {
        if (currentWorkflowStatus == WorkflowStatus.RegisteringVoters) {
            currentWorkflowStatus = WorkflowStatus.ProposalsRegistrationStarted;
            emit WorkflowStatusChange(
                WorkflowStatus.RegisteringVoters,
                WorkflowStatus.ProposalsRegistrationStarted
            );
        } else if (
            currentWorkflowStatus == WorkflowStatus.ProposalsRegistrationStarted
        ) {
            currentWorkflowStatus = WorkflowStatus.ProposalsRegistrationEnded;
            emit WorkflowStatusChange(
                WorkflowStatus.ProposalsRegistrationStarted,
                WorkflowStatus.ProposalsRegistrationEnded
            );
        } else if (
            currentWorkflowStatus == WorkflowStatus.ProposalsRegistrationEnded
        ) {
            currentWorkflowStatus = WorkflowStatus.VotingSessionStarted;
            emit WorkflowStatusChange(
                WorkflowStatus.ProposalsRegistrationEnded,
                WorkflowStatus.VotingSessionStarted
            );
        } else if (
            currentWorkflowStatus == WorkflowStatus.VotingSessionStarted
        ) {
            currentWorkflowStatus = WorkflowStatus.VotingSessionEnded;
            emit WorkflowStatusChange(
                WorkflowStatus.VotingSessionStarted,
                WorkflowStatus.VotingSessionEnded
            );
        } else if (currentWorkflowStatus == WorkflowStatus.VotingSessionEnded) {
            return (
                "Voting session has finish. You need to check the result wiht function 'getWinner'"
            );
        }
    }

    /** fonction de cloture de la session de vote */
    function _setVotesTailledStatus() private onlyOwner {
        require(
            currentWorkflowStatus != WorkflowStatus.VotesTallied,
            "votes have been already tailled"
        );
        currentWorkflowStatus = WorkflowStatus.VotesTallied;
        emit WorkflowStatusChange(
            WorkflowStatus.VotingSessionEnded,
            WorkflowStatus.VotesTallied
        );
    }

    /* fonction de relance d'un vote en cas d'égalité */
    function _relaunchVote() public onlyOwner {
        // réinitialisation du statut hasVoted des votants
        for (uint256 i = 0; i < votersAddress.length; i++) {
            voterMapping[votersAddress[i]].hasVoted = false;
        }
        // mise à zero du tableau votersAddress en vue du nouveau tour de vote
        for (uint256 i = 0; i < votersAddress.length; i++) {
            votersAddress.pop();
        }
        // relance d'un tour de vote
        currentWorkflowStatus = WorkflowStatus.VotingSessionStarted;
        emit WorkflowStatusChange(
            WorkflowStatus.VotingSessionEnded,
            WorkflowStatus.VotingSessionStarted
        );
    }

    // ----- FIN FONCTIONS DE MODIFICATION DU STATUS DU WORKFLOW

    /** addVoter : fonction de création d'un nouveau votant
     * Instancie un nouveau votant
     * L'associe à une adresse via le mapping
     * emet l'event associé */
    function addVoter(address _address) public onlyOwner {
        require(
            currentWorkflowStatus == WorkflowStatus.RegisteringVoters,
            "voter registering session has ended"
        );
        require(
            !voterMapping[_address].isRegistered,
            "this voter is already registered"
        );
        Voter memory newVoter = Voter(true, false, 0);
        voterMapping[_address] = newVoter;
        emit VoterRegistered(_address);
    }

    /** makeProposal : fonction pour faire une proposition
     * ajoute une proposition au tableau proposals
     * emet l'event associé */
    function makeProposal(string memory _description) public isVoterRegistered {
        require(
            currentWorkflowStatus ==
                WorkflowStatus.ProposalsRegistrationStarted,
            "proposal session isn't open"
        );
        Proposal memory newProposal = Proposal(_description, 0);
        proposals.push(newProposal);
        emit ProposalRegistered(proposals.length);
    }

    /** voteForProposal : fonction de vote d'un user enregistré
     * ajoute une voie à la proposition
     * modifie le status du voteur en "a voté"
     * emet l'event associé */
    function voteForProposal(uint256 _proposalId) public isVoterRegistered {
        require(
            currentWorkflowStatus == WorkflowStatus.VotingSessionStarted,
            "voting session isn't open"
        );
        require(
            _proposalId < proposals.length,
            "this proposal Id doesn't exist"
        );
        require(
            !voterMapping[msg.sender].hasVoted,
            "you have already voted for this sessions"
        );
        proposals[_proposalId].voteCount++;
        voterMapping[msg.sender].hasVoted = true;
        votersAddress.push(msg.sender);
        emit Voted(msg.sender, _proposalId);
    }

    /** getWinner : fonction identifiant la proposition gagnante
     * parcourt les proposition en gardant à chaque itération celle ayant le plus de vote
     * retourne la proposition gagnante
     * met à jour le status de la session
     * En cas d'égalité, informe l'admin */
    function getWinner()
        public
        onlyOwner
        returns (uint256 proposalId, string memory winningProposal)
    {
        require(
            currentWorkflowStatus == WorkflowStatus.VotingSessionEnded,
            "voting session still ongoing, please finish the workflow before getting the winner"
        );
        uint256 maxVoteCount;
        bool isDraw;
        for (uint256 i = 0; i < proposals.length; i++) {
            if (proposals[i].voteCount > maxVoteCount) {
                winningProposalId = i;
                maxVoteCount = proposals[i].voteCount;
                // gestion de l'égalité ==>
            } else if (proposals[i].voteCount == maxVoteCount) {
                isDraw = true;
            }
        }
        _setVotesTailledStatus();
        if (isDraw) {
            return (
                winningProposalId,
                "draw! You have to relaunch a new vote with the dedicated function"
            );
        } else {
            string memory winningProposal = proposals[winningProposalId]
                .description;
            return (winningProposalId, winningProposal);
        }
    }
}
