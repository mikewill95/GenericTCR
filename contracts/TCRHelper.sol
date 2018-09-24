pragma solidity^0.4.24;

import "./TCR.sol";
import "./Ownable.sol";
import "./PLCRVoting.sol";

/** @title TCRHelper Contract. */
contract TCRHelper is Ownable {

    event ChallengeWon(string winner, uint winningVoteCount, string loser, uint losingVoteCount, uint pollID);

    TCR tcr;

    //@dev constructor called once within the TCR constructor
    constructor(address _tcr) public {
        tcr = TCR(_tcr);
    }

    //@dev finds the index of an address on a list of addresses passed into the function
    //@param _incumbentAddress address of incumbent
    //@param _list address list passed from TCR
    //@returns integer index value
    function findIncumbentIndex(address _incumbentAddress, address[] _list) public pure returns (uint) {
        uint i;
        while (i < _list.length && _list[i] != _incumbentAddress) {
            i++;
        }
        return i;
    }

    //@dev determines if the challenger in a recently concluded vote has won. It is a helper function of processBallot
    //     in TCR
    //@param _currentPoll the pollID of the poll in session
    //@param _challenger name of list applicant
    //@param _incumbent name of list incumbent
    //@returns true if challenger won false otherwise
    function didChallengerWin(uint _currentPoll, string _challenger, string _incumbent) onlyOwner() public returns (bool) {
        PLCRVoting votingContract = PLCRVoting(tcr.votingContract());

        (uint votesForChallenger, uint votesForIncumbent) = votingContract.processOverallResultsHelper(_currentPoll);

        if (votesForChallenger > votesForIncumbent) {
            emit ChallengeWon(_challenger,votesForChallenger,_incumbent,votesForIncumbent,_currentPoll); // In the case that the challenger won
            return true;
        }
        else {
            emit ChallengeWon(_incumbent,votesForIncumbent,_challenger,votesForChallenger,_currentPoll); // In the case that the incumbent won
            return false;
        }
    }

}
