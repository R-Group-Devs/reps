# "Reps" (working title)
Governance delegation protocol

## Purpose
### General problems
**Community members cannot keep track of all their delegates over many DAOs and many decisions**, so participation will continue to be poor or delegates will have little incentive to represent their constituents.

**People are not checking up on what their delegates are doing. And even if they do check up on them, the only thing delegates stand to lose is one person's voting power.**

**Delegates are not being paid to push governance forward, and are more like hobbyists**. Hobbyist representatives might represent us well, but they probably aren't as active as we'd like in pushing DAOs towards their goals. Paid delegates whose pay depends on them doing a good job might do better.

## Proposal
Create a protocol that:
- Supports multi-community delegates (delegates can themselves be communities, i.e. political parties), allowing people to browse delegates for all their communities in the same place and delegate more than one token at once, to reduce the number of actions they need to take
- Lets delegates get paid to do governance work
- As trustlessly as possible, **keeps delegates accountable to their constituents by giving them more to lose if they break their promises**, without putting the burden on constituents to put lots of time into oversight

## User stories
DAO member:
- As a member of many DAOs, I want to view all my currently undelegated voting power
- As a member of many DAOs, I want to quickly find delegates who can represent me well in all my communities
- As a member of many DAOs, I want to quickly delegate my voting power to those delegates

Delegate:
- As a delegate, I want to present a promise about how I will act when governing
- As a delegate, I want to get paid for fulfilling my promise

Challenger:
- As a challenger, I want to get paid for finding delegates breaking their promises

## Specs
`Reps` contract:
- mints new `Rep` NFTs. Each Rep NFT contains a promiseURI and hash.
- uses the Gnosis / Snapshot pattern for delegation, in which delegations are simple data strutctures including a delegator, an id, and a delegatee. This protocol is intended to be used with Snapshot or other off-chain voting solutions. 
- boosts ETH for a Rep -- add more ETH to the payment pool / challenge bounty for a Rep's owner.
- challenges a Rep -- pay a fee to challenge a Rep, activating a dispute resolution system to determine if a Rep is upholding their `promise`. 
- "fires" a Rep -- if a challenge succeeds and a Rep is found to have broken their promise, the Rep NFT is burned, and any remaining Eth in that Rep's pool goes to the successful challenger. People delegated to that Rep will need to switch their delegation to reactivate it.

### TODOs
- [X] Decide on dispute resolution system (Kleros' interfaces)
- [ ] Talk to Snapshot about integration
- [ ] Testing
- [ ] Dapp -- frontend, subgraph, etc.

# Development
- install [Foundry](https://github.com/gakonst/foundry)
- `forge update` to install libs
- `forge build` to compile
