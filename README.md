# "Reps" (working title)
Governance delegation protocol

## Purpose
### General
Rarible DAO, and most other existing DAOs, have a need for governance power delegation in order to increase voter participation. However, the more DAOs people are members of, and the more complex governance decisions are, the more ineffective independent delegation systems will be. Community members cannot keep track of all their delegates over many DAOs and many decisions, so participation will continue to be poor or delegates will have little incentive to represent their constituents.

In DAOs with delegation systems, delegates have little skin in the game of representation. Let’s be honest: people are not checking up on what their delegates are doing. And even if they do check up on them, the only thing delegates stand to lose is a little voting power.

### Rarible DAO
We need a delegation system to reduce RARI voter apathy. That delegation system should ideally be scalable and give delegates skin in the game of representing their constituents.

More concretely, the working on this problem could provide:
- Speculative value -- this could potentially get a lot of attention in the DAO space and solve an interesting new problem
- Financial value – we can potentially get grant funding from DAOs like Compound, Uniswap, Radicle and others using delegation systems, including possible token swaps
- Utility value -- provides us with an effective RARI delegation system

## Proposal
Create a protocol that:
- Supports multi-token delegates, allowing cross-community delegates and voting systems that use multiple tokens
- As trustlessly as possible, keeps delegates accountable to their constituents by giving them more to lose if they break their promises
- Allows people locking their tokens to delegate to receive a corresponding liquid asset

## User stories
DAO member:
- As a member of many DAOs, I want to view all my currently undelegated voting power
- As a member of many DAOs, I want to quickly find delegates who can represent me well in all my communities
- As a member of many DAOs, I want to quickly delegate my voting power to those delegates

Delegator:
- As a delegator, I want to make my assets useful even while they are locked in delegation
- As a delegator, I want to un-delegate and retrieve my tokens

Delegate:
- As a delegate, I want to communicate which communities I am active in
- As a delegate, I want to present a promise about how I will act on when governing
- As a delegate, I want to get paid for fulfilling my promise
- As a delegate, I want to be able to stop being a delegate

Challenger:
- As a challenger, I want to get paid for finding delegates breaking their promises

## Specs
`Reps` contract:
- deploys new `Rep` contracts -- these include a political `promise` string and an `operator` address (can be transferred). Each Rep delegate a set of token types to the operator (the representative -- can be an EOA, multi-sig, DAO, etc.). A Rep can accept delegations in up to 10 different tokens, ERC20 and ERC721 allowed.
- creates new `delegation` NFTs -- deposit any amount / number of up to 10 ERC20/ERC721 tokens to a `Rep` contract (delegating the voting power from those tokens to that Rep's operator). When creating, you may also include some ETH that goes toward streaming payment to the Rep operator and acts as a bounty for challengers.
- burns `delegation` NFTs -- burn a given delegation NFT in order to retrieve the corresponding tokens. ETH cannot be retrieved.
- boosts ETH for a Rep -- add more ETH to the payment pool / challenge bounty for a Rep.
- challenges a Rep -- pay a fee to challenge a Rep, activating a dispute resolution system to determine if a Rep is upholding their `promise`. 
- "fires" a Rep -- if a challenge succeeds and a Rep is found to have broken their promise, the Rep contract has its tokens delegated to and operator set to the zero address, effectively "firing" the Rep. Delegations to that Rep can still be redeemed. Any remaining Eth in that Rep's pool goes to the successful challenger. The Rep contract is dead at this point, but the operator is free to create a new one and build up support again (if they can).

### TODOs
[] Decide on dispute resolution system (Kleros?)
[] Testing
[] Dapp -- frontend, subgraph, etc.

# Development
- install [Foundry](https://github.com/gakonst/foundry)
- `forge update` to install libs
- `forge build` to compile
