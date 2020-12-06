
# Plasma Alliance Governance  

## Ppay.Sol 
Governance Token PPAY. 

## GovernorPlasma.Sol 
The GovernorPlasma administrator contract of the Plasma Alliance timelock contract. Holders of Ppay token may create and vote on proposals which will be queued into the Plasma Alliance timelock and then have effects on Plasma Alliance contracts.

## Timelock.sol 
The Timelock Executor of holders' proposals. 

## PlasmaVesting.sol 
the Vesting Controls the distribution time of PPAY tokens and allows the claim of tokens on the recipient's account.

## Forked from 
https://github.com/Uniswap/governance/commit/ab22c084bacb2636a1aebf9759890063eb6e4946 
https://github.com/compound-finance/compound-protocol/tree/v2.8.1


# How to execute Mocha tests

Requirements:
   - Node.js 12.x 
   - @typescript 4.0.2 

1. yarn install 
2. yarn compile 
3. yarn test    

To lint the code, run:
 yarn lint
