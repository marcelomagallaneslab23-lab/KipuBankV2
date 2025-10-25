// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

contract ETHDevPackNFT is ERC721, Ownable {
    using Counters for Counters.Counter;
    Counters.Counter private _tokenIdCounter;
    string private _baseTokenURI;
    uint256 public constant MAX_SUPPLY = 10000;
    uint256 public mintPrice = 0.01 ether;
    bool public isSaleActive = false;

    constructor(
        string memory name,
        string memory symbol,
        string memory baseTokenURI
    ) ERC721(name, symbol) Ownable(msg.sender) {  // <-- Fix: Pasar msg.sender a Ownable
        _baseTokenURI = baseTokenURI;
    }

    // Resto del código sigue igual...
    function setSaleStatus(bool status) external onlyOwner {
        isSaleActive = status;
    }

    function mintNFT() external payable {
        require(isSaleActive, "Sale is not active");
        require(msg.value >= mintPrice, "Insufficient ETH sent");
        require(_tokenIdCounter.current() < MAX_SUPPLY, "Max supply reached");

        uint256 tokenId = _tokenIdCounter.current();
        _tokenIdCounter.increment();
        _safeMint(msg.sender, tokenId);
    }

    

}
