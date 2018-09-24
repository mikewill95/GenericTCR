pragma solidity ^0.4.24;

import "./PLCRVoting.sol";
import "./SafeMath.sol";
import "./Ownable.sol";
import "./TCRHelper.sol";
import "./AttributeStore.sol";

/** @title Generic Token Curated Registry. */
contract TCR is Ownable {

    // =======
    // EVENTS:
    // =======

    event EmptySlotFilled(string _challengerName);
    event ChallengeInitiated(string challenger, string incumbent);
    event ChallengeEnded(uint pollID);
    event ChallengeWon(string winner, uint winningVoteCount, string loser, uint losingVoteCount, uint pollID);
    event NoConsensusReached(uint pollID);
    event IncumbentGraduated(address incumbent);
    event ListUpdated(string inductee);

    // ================
    // DATA STRUCTURES:
    // ================

    using SafeMath for uint;

    enum Stages {
        PreVote,
        VoteInProgess
    }

    // ================
    // STATE VARIABLES:
    // ================


    string TCR_name;
    string[] public stringList;
    address[] public hieroglyphicList;

    mapping (string => address) linkNameToMemberAdr;
    mapping (address => string) public linkAdrToMemberName;

    string challenger;
    uint constant challengerStake = 100000 wei;

    address specialCase;

    bool public killSwitch;

    PLCRVoting public votingContract;
    Stages public stage;
    TCRHelper public tcrhelper;

    // ======
    // SETUP:
    // ======


    //@dev is called only once, initializes a new Token Curated Registry with desired properties. Embedded in this constructor
    //     is the instantiation of a TCRHelper contract and a user input check.
    //@param _name is the title of the TCR to be displayed in the UI
    //@param _length length of TCR list
    constructor(string _name, uint _length) public {
        require(bytes(_name).length <= 20);
        require(_length <= 10);
        TCR_name = _name;
        stage = Stages.PreVote;
        stringList = new string[](_length);
        hieroglyphicList = new address[](_length);
        tcrhelper = new TCRHelper(this);
    }

    //@dev should only be called once, stores an instance of the contract PLCRVoting as a state variable in this
    //     contract once it has been launched
    //@param _plcr address of the launched PLCRVoting contract
    function storePLCRVoting(address _plcr) external onlyOwner() {
        votingContract = PLCRVoting(_plcr);
    }

    // ============
    // OWNER TOOLS:
    // ============


    //@dev circuit-breaker that freezes all non-constant functions in this contract
    //@notice onlyOwner requirement
    function freezeAllMotorFunctions() external setupRequired() onlyOwner() {
        killSwitch = true;
    }

    //@dev this will resume this contract's normal operations
    //@notice onlyOwner requirement
    function resumeAllMotorFunctions() external setupRequired() onlyOwner() {
        killSwitch = false;
    }

    // ===================
    // REGISTRY INTERFACE:
    // ===================


    //@dev entities wanting to be on the list can apply to it via this function. They must send an amount of ether
    //     equal to the challengerStake and specify an incumbent that they wish to displace (or an empty string if
    //     there is a position on the list that is unfilled)
    //@notice calls initiateVote if there are no empty slots remaining and the string passed is an incumbent on the list
    //@param _challengerName name of the entity applying to the list
    //@param _incumbentName name of the incumbent the applicant wants to displace
    function applyToList(string _challengerName, string _incumbentName) external payable setupRequired() atStage(Stages.PreVote) smoothSailing() {
        require(msg.value == challengerStake);
        require(bytes(_challengerName).length <= 20);
        require(bytes(_incumbentName).length <= 20);
        challenger = _challengerName;
        address incumbentAddress = linkNameToMemberAdr[_incumbentName];
        if (keccak256(_incumbentName) == keccak256("")) {
            require(replaceIncumbent(msg.sender,0));
            emit EmptySlotFilled(_challengerName);
        }
        else if (incumbentAddress != 0) {
            initiateVote(msg.sender,incumbentAddress);
        }
        else{
            revert();
        }
    }

    //@dev after a vote is complete this function must be called to process the vote after which individual users can
    //     process their personal outcomes
    //@notice if the vote quorum is met and the vote passes, a winner is determined. If not, then the challenger is
    //     permitted to retrieve his stake. Additionally, two votes cannot be running concurrently as specified by
    //     the enum Stages
    function processBallot() external payable atStage(Stages.VoteInProgess) smoothSailing() setupRequired() {
        uint currentPoll = votingContract.currentPoll();
        require(votingContract.pollEnded(currentPoll));
        nextStage();                                    // placement combats reentrance attacks!
        emit ChallengeEnded(currentPoll);

        address challengerAddress = votingContract.currentChallenger();
        if (votingContract.isPassed(currentPoll)) {             // If the Poll reaches consensus..
            address(votingContract).call.value(challengerStake)(3000); // move loser's funds to PLCRVoting contract from TCR

            address incumbentAddress = votingContract.currentIncumbent();
            string memory incumbentName = linkAdrToMemberName[incumbentAddress];
            bool result = tcrhelper.didChallengerWin(currentPoll,challenger,incumbentName);
            if (result) {
                replaceIncumbent(challengerAddress,incumbentAddress);
            }
        }
        else{
            specialCase = challengerAddress;
            emit NoConsensusReached(currentPoll);
        }
    }

    //@dev An incumbent (or challenger in a poll that did not reach consensus) can elect to leave the list if there is
    //     no active challenge. Their information is removed from the TCR and funds returned
    //@param _incumbentOrChallengerName name of list incumbent (or special case cahllenger) seeking to graduate
    function graduate(string _incumbentOrChallengerName) atStage(Stages.PreVote) external payable atStage(Stages.PreVote) smoothSailing() setupRequired() {
        require(msg.sender == linkNameToMemberAdr[_incumbentOrChallengerName]);
        require(bytes(_incumbentOrChallengerName).length <= 20);

        linkNameToMemberAdr[_incumbentOrChallengerName] = 0;  // placement combats reentrance attacks!
        linkAdrToMemberName[msg.sender] = "";

        if (msg.sender != specialCase){
            uint result = tcrhelper.findIncumbentIndex(msg.sender,hieroglyphicList);
            hieroglyphicList[result] = 0;
            stringList[result] = "";
        }
        else {
            specialCase = 0;
        }
        msg.sender.transfer(challengerStake);
        emit IncumbentGraduated(msg.sender);
    }

    // ================
    // GENERAL HELPERS:
    // ================


    //@dev repleaces an incumbent on the TCR list in the event that a challenger wins a vote or there is an empty
    //     slot to be filled
    //@param _challengerAddress address of challenger to replace incumbent on list
    //@param _incumbentAddress address of list incumbent to be replaced by challenger
    //@returns returns true if the incumbent is replaced or empty slot filled, false otherwise
    function replaceIncumbent(address _challengerAddress, address _incumbentAddress) private returns(bool) {
        uint index = tcrhelper.findIncumbentIndex(_incumbentAddress,hieroglyphicList);
        if (index == hieroglyphicList.length) {
            return false;
        }

        hieroglyphicList[index] = _challengerAddress;
        stringList[index] = challenger;
        if (_incumbentAddress != 0) {       // if not empty space, remove incumbents credentials
            string memory incumbentName = linkAdrToMemberName[_incumbentAddress];
            linkAdrToMemberName[_incumbentAddress] = "";
            linkNameToMemberAdr[incumbentName] = 0;
        }
        else {
            linkNameToMemberAdr[challenger] = _challengerAddress;
            linkAdrToMemberName[_challengerAddress] = challenger;
        }
        emit ListUpdated(challenger);
        return true;
    }

    //@dev initiates a vote in the case that all empty slots are filled and a applicant requests to challenge an incumbent
    //@param _challengerAddress address of applicant seeking to replace incumbent
    //@param _incumbentAddress address of list incumbent
    function initiateVote(address _challengerAddress, address _incumbentAddress) private {
        nextStage();                                 // placement combats reentrance attacks!

        linkNameToMemberAdr[challenger] = _challengerAddress; // mapping dually identifies those with ether in contract
        linkAdrToMemberName[_challengerAddress] = challenger;

        votingContract.startPoll(_challengerAddress,_incumbentAddress);
        emit ChallengeInitiated(challenger,linkAdrToMemberName[_incumbentAddress]);    //^this TCR contract, not msg.sender, calls startPoll because of opcode call
    }

    //@dev Moves from one stage to the next
    function nextStage() private smoothSailing() setupRequired() {
        stage = Stages((uint(stage) + 1)% 2);
    }

    // ==========
    // MODIFIERS:
    // ==========

    //@dev Ensures a function can only be called at specified phase in voting
    modifier atStage(Stages _stage) {
        require(stage == _stage);
        _;
    }

    //@dev Ensures a function can only be called if the contract is not frozen by owner
    modifier smoothSailing() {
        require(killSwitch == false);
        _;
    }

    //@dev Ensures a function can only be called if the contract is completely set up
    modifier setupRequired() {
        require(address(votingContract) != 0);
        _;
    }

}
