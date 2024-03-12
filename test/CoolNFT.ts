import {
  time,
  loadFixture,
} from "@nomicfoundation/hardhat-toolbox/network-helpers";
import { anyValue } from "@nomicfoundation/hardhat-chai-matchers/withArgs";
import { HardhatEthersSigner } from "@nomicfoundation/hardhat-ethers/signers";
import { expect } from "chai";
import { ethers, network } from "hardhat";
import { CoolNFT } from "../typechain-types";
import { HardhatEthersHelpers } from "hardhat/types";

describe("CoolNFT", function () {
  async function deployCoolNFT() {
    const [owner, otherAccount] = await ethers.getSigners();

    const CoolNFT = await ethers.getContractFactory("CoolNFT");
    const coolNFT = await CoolNFT.deploy(owner);

    return { coolNFT, owner, otherAccount };
  }

  describe("Deployment", function () {
    it("Should set the right signer", async function () {
      const { coolNFT, owner } = await loadFixture(deployCoolNFT);

      expect(await coolNFT.mintVoucherSigner()).to.equal(owner.address);
    });

    it("Should set the right owner", async function () {
      const { coolNFT, owner } = await loadFixture(deployCoolNFT);

      expect(await coolNFT.owner()).to.equal(owner.address);
    });
  });

  describe("Mints", function () {
    describe("Single mints", function () {
      it("Should mint one nft when sent enough ether", async function () {
        const { coolNFT, otherAccount } = await loadFixture(deployCoolNFT);
        const mintPrice = await coolNFT.MINT_PRICE();

        await expect(
          coolNFT.connect(otherAccount).mint({ value: mintPrice })
        ).to.changeEtherBalances(
          [coolNFT, otherAccount],
          [mintPrice, -mintPrice]
        );

        await expect(await coolNFT.ownerOf(1)).to.equal(otherAccount);
      });

      it("Should mint a batch of nfts when sent enough ether", async function () {
        const { coolNFT, otherAccount } = await loadFixture(deployCoolNFT);
        const mintPrice = await coolNFT.MINT_BATCH_PRICE();

        await expect(
          coolNFT.connect(otherAccount).mintBatch({ value: mintPrice })
        ).to.changeEtherBalances(
          [coolNFT, otherAccount],
          [mintPrice, -mintPrice]
        );

        for (let i = 1; i < 6; i++)
          await expect(await coolNFT.ownerOf(i)).to.equal(otherAccount);
      });

      it("Should mint one nft when sent right signature", async function () {
        const { coolNFT, owner, otherAccount } = await loadFixture(
          deployCoolNFT
        );

        const signature = await GetSignature(owner, otherAccount, coolNFT);

        await coolNFT
          .connect(otherAccount)
          .signedMint(otherAccount, 0, signature);
        await expect(await coolNFT.ownerOf(1)).to.equal(otherAccount);
      });

      it("Should not mint one nft when sent signature produced by wrong signer", async function () {
        const { coolNFT, owner, otherAccount } = await loadFixture(
          deployCoolNFT
        );

        const signature = await GetSignature(
          otherAccount,
          otherAccount,
          coolNFT
        );

        await expect(
          coolNFT.connect(otherAccount).signedMint(otherAccount, 0, signature)
        ).to.be.revertedWithCustomError(coolNFT, "InvalidMintVoucherSigner");
        await expect(coolNFT.ownerOf(1)).to.be.revertedWithCustomError(
          coolNFT,
          "ERC721NonexistentToken"
        );
      });

      it("Should not mint one nft when sent wrong nonce", async function () {
        const { coolNFT, owner, otherAccount } = await loadFixture(
          deployCoolNFT
        );

        const signature = await GetSignature(owner, otherAccount, coolNFT);

        await expect(
          coolNFT.connect(otherAccount).signedMint(otherAccount, 1, signature)
        ).to.be.reverted;
        await expect(coolNFT.ownerOf(1)).to.be.revertedWithCustomError(
          coolNFT,
          "ERC721NonexistentToken"
        );
      });

      it("Should not mint one nft when sent wrong `mintTo`", async function () {
        const { coolNFT, owner, otherAccount } = await loadFixture(
          deployCoolNFT
        );

        const signature = await GetSignature(owner, otherAccount, coolNFT);

        await expect(
          coolNFT.connect(otherAccount).signedMint(owner, 0, signature)
        ).to.be.reverted;
        await expect(coolNFT.ownerOf(1)).to.be.revertedWithCustomError(
          coolNFT,
          "ERC721NonexistentToken"
        );
      });

      it("Should not mint second nft when sent the same signature", async function () {
        const { coolNFT, owner, otherAccount } = await loadFixture(
          deployCoolNFT
        );

        const signature = await GetSignature(owner, otherAccount, coolNFT);

        await coolNFT
          .connect(otherAccount)
          .signedMint(otherAccount, 0, signature);
        await expect(await coolNFT.ownerOf(1)).to.equal(otherAccount);

        await expect(
          coolNFT.connect(otherAccount).signedMint(otherAccount, 0, signature)
        ).to.be.revertedWithCustomError(coolNFT, "SignatureAlreadyUsed");
        await expect(coolNFT.ownerOf(2)).to.be.revertedWithCustomError(
          coolNFT,
          "ERC721NonexistentToken"
        );
      });

      it("Should not mint four nfts by different signatures", async function () {
        const { coolNFT, owner, otherAccount } = await loadFixture(
          deployCoolNFT
        );

        for (let i = 0; i < 3; i++) {
          const signature = await GetSignature(owner, otherAccount, coolNFT, i);
          await expect(
            coolNFT.connect(otherAccount).signedMint(otherAccount, i, signature)
          ).not.to.be.reverted;
          await expect(await coolNFT.ownerOf(i + 1)).to.be.equal(otherAccount);
        }

        // Fourth signature. The contract should revert.
        const signature = await GetSignature(owner, otherAccount, coolNFT, 4);
        await expect(
          coolNFT.connect(otherAccount).signedMint(otherAccount, 4, signature)
        ).to.be.revertedWithCustomError(coolNFT, "AllSingleMintsUsed");

        await expect(coolNFT.ownerOf(4)).to.be.revertedWithCustomError(
          coolNFT,
          "ERC721NonexistentToken"
        );
      });
    });
  });
});

async function GetSignature(
  owner: HardhatEthersSigner,
  mintTo: HardhatEthersSigner,
  coolNFT: CoolNFT,
  nonce: number = 0
) {
  const name = "CoolNFT";
  const version = "1.0";
  const chainId = network.config.chainId as number;
  const typeHash = "MintVoucher(address to,uint256 nonce)";
  const types = {
    MintVoucher: [
      { name: "to", type: "address" },
      { name: "nonce", type: "uint256" },
    ],
  };

  const domain = {
    name: name,
    version: version,
    chainId: chainId,
    verifyingContract: await coolNFT.getAddress(),
  };

  const mintVoucher = {
    to: mintTo.address,
    nonce: nonce,
  };

  const signature = await owner.signTypedData(domain, types, mintVoucher);

  return signature;
}
