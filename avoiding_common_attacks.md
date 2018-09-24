Avoiding Common attacks

Here is a list of efforts I've made to address and avoid common attacks of which we've been made aware:
  - Using SafeMath to stop uint wrap arounds and overflows
  - Ordering of logic and account maintenance within payable functions such that the user's balance recorded in a state variable mapping is updated before funds are moved to prevent reentrancy, cross-function race conditions, and denial of service with revert attacks
  - Restricting all helper functions to private to mitigate misuse of the functions
  - Using Ownable for circuit breaker and modifyParameters functions
  - Always use msg.sender instead of tx.origin
  - All arrays in the TCR contract are fixed length so looping through them doesn't exceed gas limits/break the contract
  - Validating all contract parameters and user inputs
