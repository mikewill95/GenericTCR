var TCR = artifacts.require("TCR");
var PLCRVoting = artifacts.require("PLCRVoting");

contract('TCR Test', async (accounts) => {


  function wait3Seconds() {
    return new Promise(resolve => {
      setTimeout(() => {
        resolve('Ready!');
      }, 3000);
    });
  }

  async function asyncCall3() {
    console.log('Waiting until commit/reaveal period has ended');
    var result = await wait3Seconds();
    console.log(result);
  }

  function wait1Second() {
    return new Promise(resolve => {
      setTimeout(() => {
        resolve('Now commit');
      }, 1000);
    });
  }

  async function asyncCall1() {
    console.log('Waiting a second to ensure the ballot is in the commit stage');
    var result = await wait1Second();
    console.log(result);
  }

  // Explanaion: This test is written to ensure that the kill switch built into the TCR and PLCRVoting contracts
  // work properly. It is the first function outside of the setup function storePLCRVoting and must work in order
  // to protect the contract from unintended attacks.
  it("should first freeze both the TCR and PLCRVoting contracts then resume them", async () => {
    let instanceTCR = await TCR.new("Top 5 NFL Teams 2018",5,{from:accounts[0]});
    let instancePLCRVoting = await PLCRVoting.new(100,1,1,{from: accounts[0]});
    await instanceTCR.storePLCRVoting(instancePLCRVoting.address,{from:accounts[0]});

    await instanceTCR.freezeAllMotorFunctions({from:accounts[0]});
    await instancePLCRVoting.freezeAllMotorFunctions({from:accounts[0]});

    let stateVarTCR = await instanceTCR.killSwitch();   // killSwitch is not currently public (does not have a getter) is that
    let stateVarPLCRVoting = await instancePLCRVoting.killSwitch(); // necessary??
    assert.equal(true,stateVarTCR);
    assert.equal(true,stateVarPLCRVoting);

    await instanceTCR.resumeAllMotorFunctions({from:accounts[0]});
    await instancePLCRVoting.resumeAllMotorFunctions({from:accounts[0]});
    stateVarTCR = await instanceTCR.killSwitch();
    stateVarPLCRVoting = await instancePLCRVoting.killSwitch();
    assert.equal(false,stateVarTCR);
    assert.equal(false,stateVarPLCRVoting);

  });

  // Explanation: This test ensures that when the list is first created entities can be added to the list without
  // initiating a challenge. The code initializes the contract, has one account apply to the list, and checks that
  // the entity is stored on both the list of member strings (human readable TCR list) and list of member addresses
  it("should add a member to the list", async () => {
    let instanceTCR = await TCR.new("Top 5 NFL Teams 2018",5,{from:accounts[0]});
    let instancePLCRVoting = await PLCRVoting.new(100,1,1,{from: accounts[0]});
    await instanceTCR.storePLCRVoting(instancePLCRVoting.address,{from:accounts[0]});

    await instanceTCR.applyToList("Rams","",{value:100000,from:accounts[1]});
    let stringListMember = await instanceTCR.stringList(0);
    let hieroglyphicListMember = await instanceTCR.hieroglyphicList(0);
    assert.equal("Rams",stringListMember);
    assert.equal(accounts[1],hieroglyphicListMember);

   });

   // Explanation: This test fills the list with 5 entities and initiates a vote when a sixth challenges one of the
   // current list incumbents. It specifically checks that the TCR moves to its next stage (VoteInProgress) as is
   // expected when a vote is opened.
   it("should add 5 members to list and initate challenge with the 6th", async () => {
     let instanceTCR = await TCR.new("Top 5 NFL Teams 2018",5,{from:accounts[0]});
     let instancePLCRVoting = await PLCRVoting.new(100,1,1,{from: accounts[0]});
     await instanceTCR.storePLCRVoting(instancePLCRVoting.address,{from:accounts[0]});

     await instanceTCR.applyToList("Rams","",{value:100000,from:accounts[1]});
     let stringListMember = await instanceTCR.stringList(0);
     let hieroglyphicListMember = await instanceTCR.hieroglyphicList(0);
     assert.equal("Rams",stringListMember);
     assert.equal(accounts[1],hieroglyphicListMember);

     await instanceTCR.applyToList("Patriots","",{value:100000,from:accounts[2]});
     stringListMember = await instanceTCR.stringList(1);
     hieroglyphicListMember = await instanceTCR.hieroglyphicList(1);
     assert.equal("Patriots",stringListMember);
     assert.equal(accounts[2],hieroglyphicListMember);

     await instanceTCR.applyToList("Jaguars","",{value:100000,from:accounts[3]});
     stringListMember = await instanceTCR.stringList(2);
     hieroglyphicListMember = await instanceTCR.hieroglyphicList(2);
     assert.equal("Jaguars",stringListMember);
     assert.equal(accounts[3],hieroglyphicListMember);

     await instanceTCR.applyToList("Falcons","",{value:100000,from:accounts[4]});
     stringListMember = await instanceTCR.stringList(3);
     hieroglyphicListMember = await instanceTCR.hieroglyphicList(3);
     assert.equal("Falcons",stringListMember);
     assert.equal(accounts[4],hieroglyphicListMember);

     await instanceTCR.applyToList("Texans","",{value:100000,from:accounts[5]});
     stringListMember = await instanceTCR.stringList(4);
     hieroglyphicListMember = await instanceTCR.hieroglyphicList(4);
     assert.equal("Texans",stringListMember);
     assert.equal(accounts[5],hieroglyphicListMember);

     await instanceTCR.applyToList("Chargers","Texans",{value:100000,from:accounts[6]});
     let stage = await instanceTCR.stage();
     assert.equal(stage,1)   // 1 translates to VoteInProgess

    });

  // Explanaion: a member stays on the list for as long as it likes so long as it is not voted out. If ever a list
  // incumbent wants to leave the list, the graduate function removes its credentials from the blockchain and sends
  // its security deposit of ether back to it. The test checks that the state variable mapping linkAdrToMemberName
  // is updated such that all records of the graduate are removed from the list.
  it("should add a member to list then graduate it by removing it from list and returning ether", async () => {
    let instanceTCR = await TCR.new("Top 5 NFL Teams 2018",5,{from:accounts[0]});
    let instancePLCRVoting = await PLCRVoting.new(100,1,1,{from: accounts[0]});
    await instanceTCR.storePLCRVoting(instancePLCRVoting.address,{from:accounts[0]});

    await instanceTCR.applyToList("Rams","",{value:100000,from:accounts[1]});

    await instanceTCR.graduate("Rams",{from:accounts[1]});;
    let theRecordShow = await instanceTCR.linkAdrToMemberName(accounts[1]);
    assert.equal(theRecordShow,"");

    

   });

  // Explanaion: this test builds off the rest by first filling the list with 1 member, initiating a vote when a 2nd
  // challenges the list incumbent, then allowing a curator to request voting rights, commit and reveal his votes, and
  // process his personal outcome after the result of the vote has been recorded. The test chekcs that the curator's vote
  // was recorded and the list properly updated as a result, and that the voter's token balance is updated as expected from
  // winning the vote.
  it("should fill the list and properly process a vote in which a challenger replaces the incumbent in the first spot", async () => {
    let instanceTCR = await TCR.new("Top 5 NFL Teams 2018",1,{from:accounts[0]});
    let instancePLCRVoting = await PLCRVoting.new(100,3,1,{from: accounts[0]});
    await instanceTCR.storePLCRVoting(instancePLCRVoting.address,{from:accounts[0]});

    await instancePLCRVoting.requestVotingRights({value:1,from: accounts[3]});

    await instanceTCR.applyToList("Rams","",{value:100000,from:accounts[1]});
    await instanceTCR.applyToList("Patriots","Rams",{value:100000,from:accounts[2]});

    await asyncCall1();

    await instancePLCRVoting.commitVote("0xcc69885fda6bcc1a4ace058b4a62bf5e179ea78fd58a1ccd71c22cc9b688792f",1,{from:accounts[3]});

    await asyncCall3();

    await instancePLCRVoting.revealVote(1,1,{from:accounts[3]});

    await asyncCall3();
    let hieroglyphicListMember = await instanceTCR.hieroglyphicList(0);
    await instanceTCR.processBallot({from:accounts[0]});

    hieroglyphicListMember = await instanceTCR.hieroglyphicList(0);
    assert.equal(accounts[2],hieroglyphicListMember);   // List is updated

    let preBalance = await instancePLCRVoting.voteTokenBalance(accounts[3]);
    await instancePLCRVoting.processIndividualResult(1,1,{from:accounts[3]});
    let postBalance = await instancePLCRVoting.voteTokenBalance(accounts[3]);
    assert.equal(preBalance.toString(),"0");        // Before the individual's result for the vote is processed the vote credit balance should be 0
    assert.equal(postBalance.toString(),"100001");  // After "        " should be 100001 (all of the 100000 wei challenger stake and his 1 vote credit)

  });

})
