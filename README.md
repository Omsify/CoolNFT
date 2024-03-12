# CoolNFT.

An NFT (ERC721) token contract that allows users to mint NFTs one-by-one or in batches by 6.
- There are two types of single mint function: payable (user must send ether to the contract when minting) and non-payable (user must provide an admin signature that allows him to mint the NFT. Signatures are issued via backend service).
- Minting batch at once has different per-NFT price than when minting one-by-one.
- All minting functions emit events with freshly minted tokenIds.
- Total supply of tokens is capped at 1000.
- An address can't mint more than 3 tokens one-by-one (even if the user has an admin signature allowing him to do so).
- One address can only mint a batch of 6 NFTs once.
- Contracts are designed to be gas-optimized.