var TCR = artifacts.require("./TCR.sol");
var PLCRVoting = artifacts.require("PLCRVoting.sol");
var AttributeStore = artifacts.require("./AttributeStore.sol");

module.exports = function(deployer,network,accounts) {
  deployer.deploy(AttributeStore);
  deployer.link(AttributeStore,PLCRVoting);
  deployer.deploy(PLCRVoting,100,10,1,{from:accounts[0],gas:6721975});
  deployer.link(AttributeStore,TCR);
  deployer.deploy(TCR,"Top NFL Teams 2018",5,{from:accounts[0],gas:6721975});

};
