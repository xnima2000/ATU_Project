// SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/security/Pausable.sol";

contract NFTMarketplace is Pausable {
    using Counters for Counters.Counter;
    Counters.Counter private _tokenIdCounter;

    address payable public owner;
    uint256 public listingFee;

    mapping(uint256 => Listing) public tokenIdToListing;

    struct Listing {
        address seller;
        uint256 price;
        bool isForAuction;
        uint256 startingBid;
        uint256 buyoutPrice;
        uint256 auctionEndTime;
        address currentBidder;
        uint256 currentBid;
    }

    event NFTListed(uint256 indexed tokenId, uint256 price, bool isForAuction);
    event NFTSold(uint256 indexed tokenId, address indexed buyer, uint256 price);
    event NFTBidPlaced(uint256 indexed tokenId, address indexed bidder, uint256 bidAmount);
    event AuctionEnded(uint256 indexed tokenId, address indexed winner, uint256 winningBid);

    constructor(uint256 _listingFee) {
        owner = payable(msg.sender);
        listingFee = _listingFee;
    }

    function listNFTForSale(uint256 price) external whenNotPaused {
        require(price > 0, "Price must be greater than zero");
        require(ERC721(_msgSender()).balanceOf(_msgSender()) > 0, "You do not own any NFTs");
        require(ERC721(_msgSender()).isApprovedForAll(_msgSender(), address(this)), "Contract not approved to manage NFTs");

        _tokenIdCounter.increment();
        uint256 newTokenId = _tokenIdCounter.current();
        ERC721(_msgSender()).safeTransferFrom(_msgSender(), address(this), newTokenId);

        tokenIdToListing[newTokenId] = Listing({
            seller: _msgSender(),
            price: price,
            isForAuction: false,
            startingBid: 0,
            buyoutPrice: 0,
            auctionEndTime: 0,
            currentBidder: address(0),
            currentBid: 0
        });

        emit NFTListed(newTokenId, price, false);
    }

    function buyNFT(uint256 tokenId) external payable whenNotPaused {
        Listing storage listing = tokenIdToListing[tokenId];
        require(listing.price > 0, "NFT not listed for sale");
        require(!listing.isForAuction, "NFT is listed for auction");
        require(msg.value == listing.price, "Incorrect payment amount");

        address payable seller = payable(listing.seller);
        seller.transfer(msg.value);
        ERC721(ownerOf(tokenId)).safeTransferFrom(address(this), _msgSender(), tokenId);

        emit NFTSold(tokenId, _msgSender(), msg.value);
    }

    function listNFTForAuction(uint256 startingBid, uint256 buyoutPrice, uint256 auctionDuration) external whenNotPaused {
        require(startingBid > 0, "Starting bid must be greater than zero");
        require(buyoutPrice > startingBid, "Buyout price must be greater than starting bid");
        require(auctionDuration > 0, "Auction duration must be greater than zero");
        require(ERC721(_msgSender()).balanceOf(_msgSender()) > 0, "You do not own any NFTs");
        require(ERC721(_msgSender()).isApprovedForAll(_msgSender(), address(this)), "Contract not approved to manage NFTs");

        _tokenIdCounter.increment();
        uint256 newTokenId = _tokenIdCounter.current();
        ERC721(_msgSender()).safeTransferFrom(_msgSender(), address(this), newTokenId);

        tokenIdToListing[newTokenId] = Listing({
            seller: _msgSender(),
            price: 0,
            isForAuction: true,
            startingBid: startingBid,
            buyoutPrice: buyoutPrice,
            auctionEndTime: block.timestamp + auctionDuration,
            currentBidder: address(0),
            currentBid: 0
        });

        emit NFTListed(newTokenId, startingBid, true);
    }

    function placeBid(uint256 tokenId) external payable whenNotPaused {
        Listing storage listing = tokenIdToListing[tokenId];
        require(listing.isForAuction, "NFT not listed for auction");
        require(block.timestamp < listing.auctionEndTime, "Auction has ended");
        require(msg.value > listing.currentBid, "Bid must be higher than current bid");

        if (listing.currentBidder != address(0)) {
            payable(listing.currentBidder).transfer(listing.currentBid);
        }

        listing.currentBidder = _msgSender();
        listing.currentBid = msg.value;

        emit NFTBidPlaced(tokenId, _msgSender(), msg.value);
    }

    function endAuction(uint256 tokenId) external whenNotPaused {
        Listing storage listing = tokenIdToListing[tokenId];
        require(listing.isForAuction, "NFT not listed for auction");
        require(block.timestamp >= listing.auctionEndTime, "Auction has not ended yet");

        if (listing.currentBidder != address(0)) {
            ERC721(ownerOf(tokenId)).safeTransferFrom(address(this), listing.currentBidder, tokenId);
            payable(listing.seller).transfer(listing.currentBid);
            emit AuctionEnded(tokenId, listing.currentBidder, listing.currentBid);
        } else {
            ERC721(ownerOf(tokenId)).safeTransferFrom(address(this), listing.seller, tokenId);
        }
        
        delete tokenIdToListing[tokenId];
    }

    function ownerOf(uint256 tokenId) internal view returns (address) {
        return ERC721(tokenIdToListing[tokenId].seller).ownerOf(tokenId);
    }

    // Admin functions

    function changeOwner(address payable newOwner) external onlyOwner {
        owner = newOwner;
    }

    function changeListingFee(uint256 newListingFee) external onlyOwner {
        listingFee = newListingFee;
    }

    function withdrawBalance() external onlyOwner {
        owner.transfer(address(this).balance);
    }

    modifier onlyOwner() {
        require(_msgSender() == owner, "Caller is not the owner");
        _;
    }
}
