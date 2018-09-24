
var PLCRVoting = artifacts.require("PLCRVoting");

contract('PLCRVoting Test', async (accounts) => {

  // Pauses testing for 3 seconds in order to pass through the commit and reveal phases of a ballot
  function wait3Seconds() {
    return new Promise(resolve => {
      setTimeout(() => {
        resolve('Ready!');
      }, 3000);
    });
  }

  // Function calling wait3Seconds
  async function asyncCall3() {
    console.log('Waiting until commit/reaveal period has ended');
    var result = await wait3Seconds();
    console.log(result);
  }

  // Pauses testing for 1 second after the poll is started in order to ensure the ballot is in the commit stage
  // before a vote is committed
  function wait1Second() {
    return new Promise(resolve => {
      setTimeout(() => {
        resolve('Now commit');
      }, 1000);
    });
  }

  // Function calling wait1Second
  async function asyncCall1() {
    console.log('Waiting a second to ensure the ballot is in the commit stage');
    var result = await wait1Second();
    console.log(result);
  }

  // Explanation: this test proves a curator can begin the TCR workflow by sending ether to the contract
  // in exchange for voting credits. The user sends ether and requests a token, and the test checks that
  // the user's voting credits balance (stored in voteTokenBalance map) is updated
  it("should accept a user's payment of 1 ether and grant him one voting token", async () => {
    let instancePLCRVoting = await PLCRVoting.new(100,1,1,{from: accounts[0]});
    await instancePLCRVoting.requestVotingRights({value: 1,from: accounts[1]});
    let userVoteTokenBalance = await instancePLCRVoting.voteTokenBalance(accounts[1]);
    assert.equal(userVoteTokenBalance,1);

  });

  // Explanation: this ensures that curators can withdraw their ether when they are done voting. The test
  // directly compares the vote credit balance of the curator before and after the withdrawal
  it("should take away a user's voting rights in exchange for forwarding to him his tokens", async () => {
    let instancePLCRVoting = await PLCRVoting.new(100,1,1,{from: accounts[0]});
    await instancePLCRVoting.requestVotingRights({value: 1,from: accounts[1]});

    let preWithdrawlVoteTokenBalance = await instancePLCRVoting.voteTokenBalance(accounts[1]);
    await instancePLCRVoting.withdrawVotingRights(1,{from: accounts[1]});
    let postWithdrawlVoteTokenBalance = await instancePLCRVoting.voteTokenBalance(accounts[1]);

    assert.equal(postWithdrawlVoteTokenBalance,0);
    assert.equal(preWithdrawlVoteTokenBalance,1);

  });

  // Explanation: this should initiate a new poll with the specified parameters. The test checks that the currentPoll
  // state variable is incremented from 0 to 1, which is a consequence of the poll being created.
  it("should start poll", async () => {
    let instancePLCRVoting = await PLCRVoting.new(100,1,1,{from: accounts[0]});
    await instancePLCRVoting.startPoll(accounts[1],accounts[2],{from:accounts[0]});
    let currentPoll = await instancePLCRVoting.currentPoll();
    assert.equal(currentPoll,1);

  });

  // Explanation: this tests that the contract can properly store a voter's commit hash to be revealed later. The test
  // initiates a poll and has a user request a vote credit then commit a vote with the inputted hash "0xcc69..", which the user
  // must manually input as a part of the program as well. The hash was generated in Remix by hashing 1 (voting choice) and 1 (salt)
  // together. Since the test cannot access the Poll struct, this test checks that the user has committed a vote by checking that
  // the state variable mapping hasNotProcessedPrevResult is true, which is a consequence of a user commiting a vote.
  it("should commit a user's vote for the challenger to the poll ", async () => {
    let instancePLCRVoting = await PLCRVoting.new(100,5,1,{from: accounts[0]});
    await instancePLCRVoting.requestVotingRights({value: 1,from: accounts[1]});
    await instancePLCRVoting.startPoll(accounts[2],accounts[3],{from:accounts[0]});
    await instancePLCRVoting.commitVote("0xcc69885fda6bcc1a4ace058b4a62bf5e179ea78fd58a1ccd71c22cc9b688792f",1,{from:accounts[1]});

    let boolean = await instancePLCRVoting.hasNotProcessedPrevResult(accounts[1]);
    assert.equal(boolean,true);

  });

  // Explanation: this tests that the displayPersonalWinPercentage function properly shows the win percentage of a
  // voter who voted correctly. The test has the curator request voting rights, commit a vote to a newly initiated poll,
  // reveal the vote, process his/her individual results after the vote is finished, and print his/her win %
  it("should produce the user's career win percentage from voting for the winning party", async () => {
    let instancePLCRVoting = await PLCRVoting.new(100,3,1,{from: accounts[0]});
    await instancePLCRVoting.requestVotingRights({value: 1,from: accounts[1]});
    await instancePLCRVoting.startPoll(accounts[2],accounts[3],{from:accounts[0]});

    await asyncCall1();

    await instancePLCRVoting.commitVote("0xcc69885fda6bcc1a4ace058b4a62bf5e179ea78fd58a1ccd71c22cc9b688792f",1,{from:accounts[1]});
    await asyncCall3();

    await instancePLCRVoting.revealVote(1,1,{from:accounts[1]});

    await asyncCall3();

    await instancePLCRVoting.processIndividualResult(1,1,{from:accounts[1]});
    let winPercentage = await instancePLCRVoting.displayPersonalWinPercentage({from:accounts[1]});
    assert.equal(winPercentage.toString(),"100");

  });


  // Explanation: This tests the voting functionality from start to finish and ultimately compares checks that the curator's
  // vote credit balance was accurately updated after he/she voted in a poll and the poll processed. Functions also tested
  // indirectly are revealVote, calculateWinnings, calculateWinningsHelper, reallocateTokens, and most other helper functions.
  it("should correctly process a user's outcome from voting for the winning party", async () => {
    let instancePLCRVoting = await PLCRVoting.new(100,3,1,{from: accounts[0]});
    await instancePLCRVoting.requestVotingRights({value: 1,from: accounts[1]});
    await instancePLCRVoting.startPoll(accounts[2],accounts[3],{from:accounts[0]});

    await asyncCall1();

    await instancePLCRVoting.commitVote("0xcc69885fda6bcc1a4ace058b4a62bf5e179ea78fd58a1ccd71c22cc9b688792f",1,{from:accounts[1]});

    await asyncCall3();

    await instancePLCRVoting.revealVote(1,1,{from:accounts[1]});

    await asyncCall3();

    await instancePLCRVoting.processIndividualResult(1,1,{from:accounts[1]});

    let userVoteTokenBalance = await instancePLCRVoting.voteTokenBalance(accounts[1]);
    assert.equal(userVoteTokenBalance.toString(),"100001");

  });

})
