pragma solidity ^0.4.24;

import "./AttributeStore.sol";
import "./SafeMath.sol";
import "./Ownable.sol";

/** @title Partial-Lock Commit-Reveal Voting. */
contract PLCRVoting is Ownable {

    // =======
    // EVENTS:
    // =======

    event VoteCommitted(uint pollID, uint numTokens, address  voter);
    event VoteRevealed(uint pollID, uint numTokens, uint votesFor, uint votesAgainst, uint choice, address voter);
    event PollCreated(uint voteQuorum, uint commitEndDate, uint revealEndDate, uint  pollID, address creator);
    event VotingRightsGranted(uint numTokens, address voter);
    event VotingRightsWithdrawn(uint numTokens, address voter);
    event UserResultsProcessed(address voter);
    event WinPercentageDisplayed(address voter);

    // ================
    // DATA STRUCTURES:
    // ================


    using AttributeStore for AttributeStore.Data;
    using SafeMath for uint;

    struct Poll {
        uint commitEndDate;     /// expiration date of commit period for poll
        uint revealEndDate;     /// expiration date of reveal period for poll
        uint voteQuorum;	    /// number of votes required for a proposal to pass
        uint votesFor;		    /// tally of votes supporting proposal
        uint votesAgainst;      /// tally of votes countering proposal
        uint votesCommitted;    /// tally of total votes
        mapping(address => bool) didCommit;  /// indicates whether an address committed a vote for this poll
        mapping(address => bool) didReveal;   /// indicates whether an address revealed a vote for this poll
    }

    // ================
    // STATE VARIABLES:
    // ================


    uint constant INITIAL_POLL_NONCE = 0;
    uint pollNonce;
    uint public currentPoll;

    uint portionForfeited;
    uint commitRevealDuration;
    uint voteQuorum;
    uint constant challengerStake = 100000 wei;

    bool public killSwitch;

    address public currentChallenger;
    address public currentIncumbent;

    mapping (uint => Poll) public pollMap;  // maps pollID to Poll struct
    mapping (address => uint) public voteTokenBalance; // maps user's address to their vote token account balance
    mapping (address => bool) public hasNotProcessedPrevResult;   // record of whether a voter has processed the last vote in which they participated
    mapping (address => uint[2]) public performanceRecord; // record of each register voter's performance

    AttributeStore.Data store;

    // ======
    // SETUP:
    // ======


    //@dev sets up the TCRs initial parameters, can be changed later by modifyParameters
    //@param _portionForfeited an interger between 1 and 10 that represents the percentage of a voter's token wager betweenw
    //       10 and 100 percent that will be redistributed upon incorrect vote
    //@param _commitRevealDuration duration of both the commit and reveal phases in seconds
    //@param _voteQuorum number of votes that must be cast to legitimize poll
    constructor(uint _portionForfeited, uint _commitRevealDuration, uint _voteQuorum) public inputCheck(_portionForfeited,_commitRevealDuration,_voteQuorum) {
        pollNonce = INITIAL_POLL_NONCE;
        portionForfeited = _portionForfeited;
        commitRevealDuration = _commitRevealDuration;
        voteQuorum = _voteQuorum;
    }

    //@dev circuit-breaker that freezes all non-constant functions
    function freezeAllMotorFunctions() external onlyOwner() {
        killSwitch = true;
    }

    //@dev This will resume the contract's normal operation
    function resumeAllMotorFunctions() external onlyOwner() {
        killSwitch = false;
    }

    //@dev Tool for the contract owner to reparmetrize the contract
    //@param _portionForfeited an interger between 1 and 10 that represents the percentage of a voter's token wager betweenw
    //       10 and 100 percent that will be redistributed upon incorrect vote
    //@param _commitRevealDuration duration of both the commit and reveal phases in seconds
    //@param _voteQuorum number of votes that must be cast to legitimize poll
    function modifyParameters(uint _portionForfeited, uint _commitRevealDuration, uint _voteQuorum) external inputCheck(_portionForfeited,_commitRevealDuration,_voteQuorum) onlyOwner() {
        portionForfeited = _portionForfeited;
        commitRevealDuration = _commitRevealDuration;
        voteQuorum = _voteQuorum;
    }

    // ==================
    // POLLING INTERFACE:
    // ==================


    //@dev Initiates a poll with passed parameters
    //@param _challenger the address of the entity representing the challenger in the ballot
    //@param _incumbent the address of the entity representing the list incumbent in the ballot
    //@return pollID Integer identifier associated with created poll
    function startPoll(address _challenger, address _incumbent) external smoothSailing() returns (uint) {
        pollNonce = pollNonce+1;
        currentPoll = pollNonce;

        currentChallenger = _challenger;
        currentIncumbent = _incumbent;

        uint commitEndDate = block.timestamp.add(commitRevealDuration);
        uint revealEndDate = commitEndDate.add(commitRevealDuration);
        pollMap[pollNonce] = Poll({
            voteQuorum: voteQuorum,
            commitEndDate: commitEndDate,
            revealEndDate: revealEndDate,
            votesFor: 0,
            votesAgainst: 0,
            votesCommitted: 0
        });

        emit PollCreated(voteQuorum, commitEndDate, revealEndDate, pollNonce, msg.sender);

        return pollNonce;
    }

    // =================
    // VOTING INTERFACE:
    // =================


    //@dev voter can commit votes to open poll if they have processed their result in the most recent poll in which they
    //     participated (or have not yet particpated in one). They must have enough voting credits for the number of votes
    //     they wish to cast
    //@notice Commits vote using hash of choice and secret salt to conceal vote until reveal
    //@param _secretHash Commit keccak256 hash of voter's choice and salt (tightly packed in this order)
    //@param _numTokens The number of vote credits to be committed towards the target poll
    function commitVote(bytes32 _secretHash, uint _numTokens) external smoothSailing() {
        require(commitPeriodActive(currentPoll));
        require(!hasNotProcessedPrevResult[msg.sender]);
        require(voteTokenBalance[msg.sender] >= _numTokens);
        require(_secretHash != 0);

        hasNotProcessedPrevResult[msg.sender] = true;    // Requiring voter to process results before committing again
                                                         // ^ placement combats reentrance attacks!
        bytes32 UUID = attrUUID(msg.sender, currentPoll);

        voteTokenBalance[msg.sender] -= _numTokens;
        pollMap[currentPoll].votesCommitted += _numTokens;
        store.setAttribute(UUID, "numTokens", _numTokens);
        store.setAttribute(UUID, "commitHash", uint(_secretHash));

        performanceRecord[msg.sender][1] += 1;            // Record that a user has participated in vote
        pollMap[currentPoll].didCommit[msg.sender] = true;
        emit VoteCommitted(currentPoll, _numTokens, msg.sender);
    }

    //@notice Reveals vote with choice and secret salt used in generating commitHash to attribute committed tokens
    //@param _voteOption Vote choice used to generate commitHash for associated poll
    //@param _salt Secret number used to generate commitHash for associated poll
    function revealVote(uint _voteOption, uint _salt) external smoothSailing() {
        require(revealPeriodActive(currentPoll));
        require(pollMap[currentPoll].didCommit[msg.sender]);                         // make sure user has committed a vote for this poll
        require(!pollMap[currentPoll].didReveal[msg.sender]);                        // prevent user from revealing multiple times
        require(keccak256(_voteOption,_salt) == getCommitHash(msg.sender, currentPoll)); // compare resultant hash from inputs to original commitHash

        pollMap[currentPoll].didReveal[msg.sender] = true;      // placement combats reentrance attacks!

        uint numTokens = getNumCommittedTokens(msg.sender, currentPoll);

        if (_voteOption == 1) {     // a vote of 1 is in support of challenger, anything else is in support of incumbent
            pollMap[currentPoll].votesFor += numTokens;
        }
        else {
            pollMap[currentPoll].votesAgainst += numTokens;
        }

        emit VoteRevealed(currentPoll, numTokens, pollMap[currentPoll].votesFor, pollMap[currentPoll].votesAgainst, _voteOption, msg.sender);
    }

    //@dev function called by voters to process the result of the poll. Voters cannot vote again until they have procesed
    //     the most recent poll they participated Integer
    //@notice all the voters' funds are locked in the contract until they process result
    //        AND a user must reveal vote in order to win tokens, otherwise loss is assumed
    //@param _pollID Integer identifier associated with target poll
    //@param _salt Arbitrarily chosen integer used to generate secretHash
    function processIndividualResult(uint _pollID, uint _salt) external smoothSailing() {
        require(pollEnded(_pollID));
        require(pollMap[_pollID].didCommit[msg.sender]);
        require(hasNotProcessedPrevResult[msg.sender]);

        hasNotProcessedPrevResult[msg.sender] = false;  // placement combats reentrace attacks!

        uint winnings;
        if (isPassed(_pollID) && pollMap[_pollID].didReveal[msg.sender]) {  // By adding reveal condition a user can only
            winnings = calculateWinnings(_pollID,_salt,msg.sender);         // win if they revealed their vote
            reallocateTokens(winnings, msg.sender, _pollID);
        }
        else if (isPassed(_pollID) && !pollMap[_pollID].didReveal[msg.sender]){
            reallocateTokens(winnings, msg.sender, _pollID);
        }

        uint userVoteCount = getNumCommittedTokens(msg.sender, _pollID);
        store.setAttribute(attrUUID(msg.sender, _pollID), "numTokens", 0);  // Clear the voter's locked token balance
        voteTokenBalance[msg.sender] += userVoteCount;          // return principle

        emit UserResultsProcessed(msg.sender);
    }

    // ================
    // TOKEN INTERFACE:
    // ================


    //@dev exchanges wei for voting credits
    function requestVotingRights() public smoothSailing() payable {
        uint amount = uint(msg.value);
        voteTokenBalance[msg.sender] += amount;
        emit VotingRightsGranted(msg.value, msg.sender);
    }

    //@dev Withdraw _numTokens ERC20 tokens from the voting contract, revoking these voting rights
    //@param _numTokens The number of ERC20 tokens desired in exchange for voting rights
    function withdrawVotingRights(uint _numTokens) external smoothSailing() payable {
        require(!hasNotProcessedPrevResult[msg.sender]);

        uint tokens = voteTokenBalance[msg.sender];
        require(tokens >= _numTokens);

        voteTokenBalance[msg.sender] -= _numTokens;         // placement combats reentrance attacks!

        msg.sender.transfer(_numTokens);
        emit VotingRightsWithdrawn(_numTokens, msg.sender);
    }

    // ----------------
    // GENERAL HELPERS:
    // ----------------


    //@dev calculates the amount of tokens a voter should recieve given their voter
    //@notice helper function for processIndividualResult
    //@param _pollID Integer identifier associated with target poll
    //@param _salt the salt with which the voter created their secret voting hash
    //@param _voter the voter whose winnings will be calculated
    //@return uint number of tokens
    function calculateWinnings(uint _pollID, uint _salt, address _voter) private constant returns (uint) {
        uint winningChoice = isPassed(_pollID) ? 1 : 0;
        bytes32 winnerHash = keccak256(winningChoice, _salt);
        bytes32 commitHash = getCommitHash(_voter, _pollID);

        uint userVoteCount = getNumCommittedTokens(_voter, _pollID);
        if (winningChoice == 1 && winnerHash == commitHash){    // Challenger wins
            return calculateWinningsHelper(_pollID,userVoteCount,pollMap[_pollID].votesFor);
        }
        else if (winningChoice != 1 && winnerHash == commitHash) {    // Incumbent wins
            return calculateWinningsHelper(_pollID,userVoteCount,pollMap[_pollID].votesAgainst);
        }
    }

    //@dev helper function of calculateWinnings that offloads the heavy computation
    //@returns value of the individual's winnings
    function calculateWinningsHelper(uint _pollID, uint _userVoteCount,uint _totalWinningVotes) public constant returns (uint winnings) {
        uint losingVotes = (pollMap[_pollID].votesCommitted).sub(_totalWinningVotes); // All incorrect votes and non revealed votes
        winnings = ((_userVoteCount.mul(portionForfeited).mul(losingVotes)).div(_totalWinningVotes.mul(100))); // Winnings from other voters
        winnings += (_userVoteCount.mul(challengerStake.div(_totalWinningVotes))); // Winnings from challenger/incumbent
    }

    //@dev after having determined the amount, if any, of tokens a voter should receive, function credits voter's account
    //@notice helper function for processIndividualResult
    //@param _winnings amount of tokens voter has won from correct vote (or zero if incorrect)
    //@param _voter voter who's tokens will be reallocated
    //@param _pollID Integer identifier associated with target poll
    function reallocateTokens(uint _winnings, address _voter, uint _pollID) private {
        uint userVoteCount = getNumCommittedTokens(_voter, _pollID);
        if (_winnings == 0) {
            voteTokenBalance[_voter].sub((portionForfeited.mul(userVoteCount)).div(100));
        }
        else{
            voteTokenBalance[_voter] += _winnings;
            performanceRecord[_voter][0] += 1;
        }
    }

    //@dev counts votes in poll
    //@notice Ultimately passes the number of votes for and against a poll to the TCR contract
    //@param _pollID Integer identifier associated with target poll
    //@return the votes for and against a challenger in agiven vote
    function processOverallResultsHelper(uint _pollID) external constant returns (uint,uint) {
        require(pollEnded(_pollID));
        return (pollMap[_pollID].votesFor, pollMap[_pollID].votesAgainst);
    }

    //@dev Constant function called by voter to reveal their win percentage
    //@return win percentage as uint
    function displayPersonalWinPercentage() external constant returns (uint) {
        uint numerator = performanceRecord[msg.sender][0];
        numerator = numerator.mul(100);
        uint denominator = performanceRecord[msg.sender][1];
        emit WinPercentageDisplayed(msg.sender);
        uint result = uint(numerator/denominator);
        return result;
    }

    //@dev Checks if an expiration date has been reached
    //@param _terminationDate Integer timestamp of date to compare current timestamp with
    //@return expired Boolean indication of whether the terminationDate has passed
    function isExpired(uint _terminationDate) constant public returns (bool expired) {
        return (block.timestamp > _terminationDate);
    }

    //@dev ensures the circuit breaker has not been switched on
    modifier smoothSailing() {
        require(killSwitch == false);
        _;
    }

    //@dev ensures user input is within an acceptable range 
    modifier inputCheck(uint _portionForfeited, uint _commitRevealDuration, uint _voteQuorum) {
      require(_portionForfeited <= 100);
      require(_commitRevealDuration <= (60*60*24*7)); // 7 days
      require(_voteQuorum > 0);
      _;
    }


    // ----------------
    // POLLING HELPERS:
    // ----------------


    //@notice Determines if poll is over
    //@dev Checks isExpired for specified poll's revealEndDate
    //@param _pollID Integer identifier associated with target poll
    //@return Boolean indication of whether polling period is over
    function pollEnded(uint _pollID) public constant returns (bool ended) {
        require(pollExists(_pollID));

        ended = isExpired(pollMap[_pollID].revealEndDate);

    }

    //@notice Checks if the commit period is still active for the specified poll
    //@dev Checks isExpired for the specified poll's commitEndDate
    //@param _pollID Integer identifier associated with target poll
    //@return Boolean indication of isCommitPeriodActive for target poll
    function commitPeriodActive(uint _pollID) constant public returns (bool) {
        require(pollExists(_pollID));

        return !isExpired(pollMap[_pollID].commitEndDate);
    }

    //@notice Checks if the reveal period is still active for the specified poll
    //@dev Checks isExpired for the specified poll's revealEndDate
    //@param _pollID Integer identifier associated with target poll
    function revealPeriodActive(uint _pollID) constant public returns (bool) {
        require(pollExists(_pollID));

        return !isExpired(pollMap[_pollID].revealEndDate) && !commitPeriodActive(_pollID);
    }

    //@dev Checks if user has committed for specified poll
    //@param _voter Address of user to check against
    //@param _pollID Integer identifier associated with target poll
    //@return Boolean indication of whether user has committed
    function didCommit(address _voter, uint _pollID) constant public returns (bool) {
        require(pollExists(_pollID));

        return pollMap[_pollID].didCommit[_voter];
    }

    //@dev Checks if user has revealed for specified poll
    //@param _voter Address of user to check against
    //@param _pollID Integer identifier associated with target poll
    //@return Boolean indication of whether user has revealed
    function didReveal(address _voter, uint _pollID) constant public returns (bool) {
        require(pollExists(_pollID));

        return pollMap[_pollID].didReveal[_voter];
    }

    //@dev Checks if a poll exists
    //@param _pollID Integer identifier associated with target poll
    //@return Boolean Indicates whether a poll exists for the provided pollID
    function pollExists(uint _pollID) constant public returns (bool) {
        return (_pollID != 0 && _pollID <= pollNonce);
    }

    //@dev Check if totalVotes exceeds votesQuorum (requires pollEnded)
    //@notice Determines if proposal has passed
    //@param _pollID Integer identifier associated with target poll
    function isPassed(uint _pollID) public constant returns (bool) {
        require(pollEnded(_pollID));

        Poll memory poll = pollMap[_pollID];
        bool result = poll.votesCommitted >= poll.voteQuorum;

        return result;
    }

    // ------------------------
    // ATTRIBUTE STORE HELPERS:
    // ------------------------


    //@dev Gets the bytes32 commitHash property of voter in target poll
    //@param _voter Address of user to check against
    //@param _pollID Integer identifier associated with target poll
    //@return Bytes32 hash property attached to target poll
    function getCommitHash(address _voter, uint _pollID) constant public returns (bytes32) {
        return bytes32(store.getAttribute(attrUUID(_voter, _pollID), "commitHash"));
    }

    //@dev Wrapper for getAttribute with attrName="numTokens"
    //@param _voter Address of user to check against
    //@param _pollID Integer identifier associated with target poll
    //@return Number of tokens committed to poll in sorted poll-linked-list
    function getNumCommittedTokens(address _voter, uint _pollID) constant public returns (uint) {
        return store.getAttribute(attrUUID(_voter, _pollID), "numTokens");
    }

    //@dev Generates an identifier which associates a user and a poll together
    //@param _pollID Integer identifier associated with target poll
    //@return UUID Hash which is deterministic from _user and _pollID
    function attrUUID(address _user, uint _pollID) public pure returns (bytes32) {
        return keccak256(_user,_pollID);
    }


}
