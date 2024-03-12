// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// May change for Solmate/~*Solady*~ for gas savings
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract CoolNFT is ERC721, Ownable, EIP712 {
    uint256 public constant MINT_PRICE = 0.1 ether;
    uint256 public constant MINT_BATCH_PRICE = 0.5 ether;
    uint256 public constant MAX_SUPPLY = 1000;
    uint256 public constant BATCH_MINT_AMOUNT = 6;
    uint256 public constant MAX_ADDRESS_SINGLE_MINT_AMOUNT = 3;

    address public immutable mintVoucherSigner;

    // Storage variables
    uint256 public supply;
    // One mapping to save minted amounts to have substantial gas savings on the SSTORE opcode.
    // The mapping possible states are: 0,1,2,3,6,7,8,9. We allow minting one when value is 0,1,2,6,7,8.
    // And allow minting a batch of 6 when value is 0,1,2,3.
    // IMPORTANT: The contract assumes that BATCH_MINT_AMOUNT>MAX_ADDRESS_SINGLE_MINT_AMOUNT.
    mapping(address user => uint256 totalMinted) public amountOfMintedByUser;
    mapping(address user => mapping(uint256 nonce => bool)) public signatureNonceUsed;

    // Events
    event Mint(address indexed mintTo, uint256 tokenId);
    event MintBySignature(address indexed mintTo, uint256 indexed nonce, uint256 tokenId);
    event BatchMint(address indexed mintTo, uint256[BATCH_MINT_AMOUNT] tokenIds);

    // Custom errors are used instead of revert strings to save on gas.
    error InsufficientEtherToMint();
    error EtherTransferFailed();
    error AllAlreadyMinted();
    error InvalidSignerInConstructor();
    error InvalidMintVoucherSigner();
    error SignatureAlreadyUsed();
    error BatchMintExceedsMaxSupply();
    error AllSingleMintsUsed();
    error BatchMintUsed();

    constructor(address mintVoucherSigner_) ERC721("CoolNFT", "CNFT") Ownable(msg.sender) EIP712("CoolNFT", "1.0") {
        if (mintVoucherSigner_==address(0)) revert InvalidSignerInConstructor();
        mintVoucherSigner = mintVoucherSigner_;
    }
    
    /// @notice Mints a single NFT to caller.
    /// @notice At least `MINT_PRICE` ether must be sent along the call.
    function mint() external payable {
        if (msg.value<MINT_PRICE) revert InsufficientEtherToMint();

        uint256 cachedAmountMinted = amountOfMintedByUser[msg.sender];        
        _verifyAbleToMintSingle(cachedAmountMinted);

        uint256 newTokenId = _mintOne(msg.sender);
        amountOfMintedByUser[msg.sender] = cachedAmountMinted + 1;

        emit Mint(msg.sender, newTokenId);
    }

    /// @notice Mints a single NFT to caller by voucher (signature).
    /// @param mintTo An address to mint NFT to (provided by backend).
    /// @param sigNonce Nonce of the signature (provided by backend).
    /// @param signature Mint voucher signature (provided by backend).
    function signedMint(address mintTo, uint256 sigNonce, bytes memory signature) external {
        if (signatureNonceUsed[mintTo][sigNonce]) revert SignatureAlreadyUsed();

        // mintTo parameter guards from front-run attacks.
        bytes32 digest = _hashTypedDataV4(keccak256(abi.encode(
            keccak256("MintVoucher(address to,uint256 nonce)"),
            mintTo,
            sigNonce
        )));
        // OpenZeppelin ECDSA contract has built-in protection from signature malleability.
        address signer = ECDSA.recover(digest, signature);
        if (signer!=mintVoucherSigner) revert InvalidMintVoucherSigner();

        uint256 cachedAmountMinted = amountOfMintedByUser[msg.sender];
        _verifyAbleToMintSingle(cachedAmountMinted);

        // Checks passed, mint the token
        uint256 newTokenId = _mintOne(mintTo);

        signatureNonceUsed[mintTo][sigNonce] = true;
        amountOfMintedByUser[msg.sender] = cachedAmountMinted + 1;

        emit MintBySignature(mintTo, sigNonce, newTokenId);
    }

    /// @notice Mints a batch (`BATCH_MINT_AMOUNT`) of NFTs to caller.
    /// @notice At least `MINT_BATCH_PRICE` ether must be sent along the call.
    function mintBatch() external payable {
        if (msg.value<MINT_BATCH_PRICE) revert InsufficientEtherToMint();

        uint256 cachedAmountMinted = amountOfMintedByUser[msg.sender];
        _verifyAbleToMintBatch(cachedAmountMinted);

        // Cache the storage variable on stack to save on gas.
        uint256 supplyCached = supply;
        if (supplyCached+BATCH_MINT_AMOUNT > MAX_SUPPLY) revert BatchMintExceedsMaxSupply();

        // No need to cache the loop variable to optimize in new Solidity versions
        uint256[BATCH_MINT_AMOUNT] memory ids;
        for (uint256 i = 1; i < BATCH_MINT_AMOUNT+1; i++) {
            uint256 currentId = supplyCached+i;
            ids[i-1] = currentId;
            _mint(msg.sender, currentId);
        }

        supply = supplyCached+BATCH_MINT_AMOUNT;
        amountOfMintedByUser[msg.sender] = cachedAmountMinted + BATCH_MINT_AMOUNT;

        emit BatchMint(msg.sender, ids);
    }

    // I assume there should be a function for owner to withdraw ether
    // from the contract unless this is a ether burn-for-charity NFT project :)
    /// @notice Withdraws all the ether from the contract.
    /// @notice Can only be called by contract's owner.
    function withdrawEth() external onlyOwner {
        (bool success,) = msg.sender.call("");
        if (!success) revert EtherTransferFailed();
    }

    /// @dev mints one nft to `mintTo` address and checks the totalSupply invariant.
    function _mintOne(address mintTo) private returns(uint256) {
        // Cache the storage variable on stack to save on gas.
        uint256 newSupplyCached = supply + 1;
        if (newSupplyCached > MAX_SUPPLY) revert AllAlreadyMinted();

        _mint(mintTo, newSupplyCached);
        supply = newSupplyCached;

        return newSupplyCached;
    }

    /// @dev verifies that the user is able to mint one nft. Reverts in false case.
    function _verifyAbleToMintSingle(uint256 amountAlreadyMinted) private pure {
        // require value in {0,1,2,6,7,8}. Read `amountOfMintedByUser` comment.
        if ((amountAlreadyMinted<BATCH_MINT_AMOUNT && amountAlreadyMinted>=MAX_ADDRESS_SINGLE_MINT_AMOUNT)
            || 
            (amountAlreadyMinted>=(BATCH_MINT_AMOUNT+MAX_ADDRESS_SINGLE_MINT_AMOUNT)))
                { revert AllSingleMintsUsed();}
    }

    /// @dev verifies that the user is able to mint a batch of nfts. Reverts in false case.
    function _verifyAbleToMintBatch(uint256 amountAlreadyMinted) private pure {
        // Require value in {0,1,2,3}. Read `amountOfMintedByUser` comment.
        if (amountAlreadyMinted>MAX_ADDRESS_SINGLE_MINT_AMOUNT) revert BatchMintUsed();
    }
}
