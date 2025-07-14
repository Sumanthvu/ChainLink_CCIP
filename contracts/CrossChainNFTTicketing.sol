// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IAny2EVMMessageReceiver {
  function ccipReceive(Client.Any2EVMMessage calldata message) external;
}

contract OwnerIsCreator {
    address private s_owner;

    constructor() {
        s_owner = msg.sender;
    }

    modifier onlyOwner() {
        require(msg.sender == s_owner, "Only owner can call this function");
        _;
    }

    function owner() public view returns (address) {
        return s_owner;
    }
}

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import { IRouterClient } from "@chainlink/contracts-ccip/contracts/interfaces/IRouterClient.sol";
import { Client } from "@chainlink/contracts-ccip/contracts/libraries/Client.sol";
import { CCIPReceiver } from "@chainlink/contracts-ccip/contracts/applications/CCIPReceiver.sol";

contract CrossChainNFTTicketing is ERC721, CCIPReceiver, Ownable, ReentrancyGuard {
    uint64 public constant SEPOLIA_CHAIN_SELECTOR = 16015286601757825753;
    uint64 public constant FUJI_CHAIN_SELECTOR = 14767482510784806043;
    uint64 public constant AMOY_CHAIN_SELECTOR = 16281711391670634445;

    enum MessageType {
        EVENT_CREATION,
        TICKET_PURCHASE
    }

    IRouterClient private immutable i_router;
    uint64 private immutable currentChainSelector;
    uint256 private eventIdCounter;
    uint256 private ticketIdCounter;

    struct Event {
        uint256 eventId;
        address organizer;
        string name;
        string description;
        uint256 ticketPrice;
        uint64 sourceChainSelector;
        uint256 totalTickets;
        uint256 soldTickets;
        bool isActive;
        bool exists;
    }

    struct EventCreationMessage {
        uint256 eventId;
        address organizer;
        string name;
        string description;
        uint256 ticketPrice;
        uint64 sourceChainSelector;
        uint256 totalTickets;
    }

    struct TicketPurchaseMessage {
        uint256 eventId;
        address buyer;
        uint256 ticketId;
    }

    struct CCIPMessage {
        MessageType messageType;
        bytes data;
    }

    mapping(uint256 => Event) public events;
    mapping(uint256 => mapping(address => bool)) public hasTicket;
    mapping(address => uint256[]) public userTickets;
    mapping(uint256 => uint256) public ticketToEvent;
    mapping(uint64 => bool) public supportedChains;

    event EventCreated(uint256 indexed eventId, address indexed organizer, string name, uint256 ticketPrice, uint64 sourceChainSelector);
    event EventSynced(uint256 indexed eventId, uint64 indexed fromChain, string name);
    event TicketPurchased(uint256 indexed eventId, address indexed buyer, uint256 ticketPrice, bool isLocalMint);
    event TicketMinted(uint256 indexed eventId, address indexed buyer, uint256 indexed ticketId);
    event CrossChainMintRequested(uint256 indexed eventId, address indexed buyer, uint64 indexed destinationChain);

    modifier onlySupportedChain(uint64 chainSelector) {
        require(supportedChains[chainSelector], "Chain not supported");
        _;
    }

    modifier eventExists(uint256 eventId) {
        require(events[eventId].exists, "Event does not exist");
        _;
    }

    constructor(address _ccipRouter, uint64 _currentChainSelector)
        ERC721("CrossChainTicket", "CCT")
        CCIPReceiver(_ccipRouter)
        Ownable(msg.sender)
    {
        i_router = IRouterClient(_ccipRouter);
        currentChainSelector = _currentChainSelector;
        supportedChains[SEPOLIA_CHAIN_SELECTOR] = true;
        supportedChains[FUJI_CHAIN_SELECTOR] = true;
        supportedChains[AMOY_CHAIN_SELECTOR] = true;
        }
function createEvent(string memory _name, string memory _description, uint256 _ticketPrice, uint256 _totalTickets) external payable {
        require(_ticketPrice > 0 && _totalTickets > 0 && bytes(_name).length > 0, "Invalid event data");
        eventIdCounter++;
        uint256 eventId = eventIdCounter;

        events[eventId] = Event({
            eventId: eventId,
            organizer: msg.sender,
            name: _name,
            description: _description,
            ticketPrice: _ticketPrice,
            sourceChainSelector: currentChainSelector,
            totalTickets: _totalTickets,
            soldTickets: 0,
            isActive: true,
            exists: true
        });

        emit EventCreated(eventId, msg.sender, _name, _ticketPrice, currentChainSelector);
        _syncEventToAllChains(eventId, msg.sender, _name, _description, _ticketPrice, _totalTickets);
    }

    function _syncEventToAllChains(uint256 eventId, address organizer, string memory name, string memory description, uint256 ticketPrice, uint256 totalTickets) internal {
        uint64[] memory chains = _getSupportedChains();
        uint256 totalFees = _calculateTotalEventSyncFees(eventId, organizer, name, description, ticketPrice, totalTickets);
        require(msg.value >= totalFees, "Insufficient CCIP fees");

        for (uint256 i = 0; i < chains.length; i++) {
            if (chains[i] != currentChainSelector) {
                _sendEventCreationMessage(eventId, organizer, name, description, ticketPrice, totalTickets, chains[i]);
            }
        }
    }

    function _sendEventCreationMessage(uint256 eventId, address organizer, string memory name, string memory description, uint256 ticketPrice, uint256 totalTickets, uint64 destinationChain) internal {
        EventCreationMessage memory eventMsg = EventCreationMessage({
            eventId: eventId,
            organizer: organizer,
            name: name,
            description: description,
            ticketPrice: ticketPrice,
            sourceChainSelector: currentChainSelector,
            totalTickets: totalTickets
        });

        CCIPMessage memory ccipMsg = CCIPMessage({
            messageType: MessageType.EVENT_CREATION,
            data: abi.encode(eventMsg)
        });

        _sendCCIPMessage(ccipMsg, destinationChain);
    }

    function buyTicket(uint256 eventId) external payable nonReentrant eventExists(eventId) {
        Event storage eventDetails = events[eventId];
        require(eventDetails.isActive && eventDetails.soldTickets < eventDetails.totalTickets && !hasTicket[eventId][msg.sender] && msg.value >= eventDetails.ticketPrice, "Cannot buy ticket");

        (bool success, ) = eventDetails.organizer.call{value: eventDetails.ticketPrice}("");
        require(success, "Payment transfer failed");
        eventDetails.soldTickets++;

        if (currentChainSelector == eventDetails.sourceChainSelector) {
            _mintTicketLocally(eventId, msg.sender);
            emit TicketPurchased(eventId, msg.sender, eventDetails.ticketPrice, true);
        } else {
            _requestCrossChainMint(eventId, msg.sender, eventDetails.sourceChainSelector);
            emit TicketPurchased(eventId, msg.sender, eventDetails.ticketPrice, false);
        }
    }

    function _mintTicketLocally(uint256 eventId, address buyer) internal {
        ticketIdCounter++;
        uint256 ticketId = ticketIdCounter;
        hasTicket[eventId][buyer] = true;
        userTickets[buyer].push(eventId);
        ticketToEvent[ticketId] = eventId;
        _safeMint(buyer, ticketId);
        emit TicketMinted(eventId, buyer, ticketId);
    }

    function _requestCrossChainMint(uint256 eventId, address buyer, uint64 sourceChain) internal {
        ticketIdCounter++;
        uint256 ticketId = ticketIdCounter;

        TicketPurchaseMessage memory ticketMsg = TicketPurchaseMessage({
            eventId: eventId,
            buyer: buyer,
            ticketId: ticketId
        });

        CCIPMessage memory ccipMsg = CCIPMessage({
            messageType: MessageType.TICKET_PURCHASE,
            data: abi.encode(ticketMsg)
        });

        _sendCCIPMessage(ccipMsg, sourceChain);
        emit CrossChainMintRequested(eventId, buyer, sourceChain);
    }

    function _ccipReceive(Client.Any2EVMMessage memory message) internal override {
        CCIPMessage memory ccipMsg = abi.decode(message.data, (CCIPMessage));

        if (ccipMsg.messageType == MessageType.EVENT_CREATION) {
            _handleEventCreationMessage(ccipMsg.data, message.sourceChainSelector);
        } else if (ccipMsg.messageType == MessageType.TICKET_PURCHASE) {
            _handleTicketPurchaseMessage(ccipMsg.data, message.sourceChainSelector);
        }
    }

    function _handleEventCreationMessage(bytes memory data, uint64 sourceChain) internal {
        EventCreationMessage memory eventMsg = abi.decode(data, (EventCreationMessage));
        if (!events[eventMsg.eventId].exists) {
            events[eventMsg.eventId] = Event({
                eventId: eventMsg.eventId,
                organizer: eventMsg.organizer,
                name: eventMsg.name,
                description: eventMsg.description,
                ticketPrice: eventMsg.ticketPrice,
                sourceChainSelector: eventMsg.sourceChainSelector,
                totalTickets: eventMsg.totalTickets,
                soldTickets: 0,
                isActive: true,
                exists: true
            });
            emit EventSynced(eventMsg.eventId, sourceChain, eventMsg.name);
        }
    }

    function _handleTicketPurchaseMessage(bytes memory data, uint64 sourceChain) internal {
        TicketPurchaseMessage memory ticketMsg = abi.decode(data, (TicketPurchaseMessage));
        hasTicket[ticketMsg.eventId][ticketMsg.buyer] = true;
        userTickets[ticketMsg.buyer].push(ticketMsg.eventId);
        ticketToEvent[ticketMsg.ticketId] = ticketMsg.eventId;
        _safeMint(ticketMsg.buyer, ticketMsg.ticketId);
        emit TicketMinted(ticketMsg.eventId, ticketMsg.buyer, ticketMsg.ticketId);
    }

    function _sendCCIPMessage(CCIPMessage memory ccipMsg, uint64 destinationChain) internal {
        bytes memory encodedMessage = abi.encode(ccipMsg);
        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(address(this)),
            data: encodedMessage,
            tokenAmounts: new Client.EVMTokenAmount[](0),
            extraArgs: Client._argsToBytes(Client.EVMExtraArgsV1({gasLimit: 400_000})),
            feeToken: address(0)
        });

        uint256 ccipFee = i_router.getFee(destinationChain, message);
        require(address(this).balance >= ccipFee, "Insufficient balance for CCIP fees");
        i_router.ccipSend{value: ccipFee}(destinationChain, message);
    }

    function _getSupportedChains() internal pure returns (uint64[] memory) {
        uint64[] memory chains = new uint64[](3);
        chains[0] = SEPOLIA_CHAIN_SELECTOR;
        chains[1] = FUJI_CHAIN_SELECTOR;
        chains[2] = AMOY_CHAIN_SELECTOR;
        return chains;
    }

    function _calculateTotalEventSyncFees(uint256 eventId, address organizer, string memory name, string memory description, uint256 ticketPrice, uint256 totalTickets) internal view returns (uint256) {
        uint256 totalFees = 0;
        uint64[] memory chains = _getSupportedChains();
        EventCreationMessage memory eventMsg = EventCreationMessage({eventId: eventId, organizer: organizer, name: name, description: description, ticketPrice: ticketPrice, sourceChainSelector: currentChainSelector, totalTickets: totalTickets});
        CCIPMessage memory ccipMsg = CCIPMessage({messageType: MessageType.EVENT_CREATION, data: abi.encode(eventMsg)});
        bytes memory encodedMessage = abi.encode(ccipMsg);

        for (uint256 i = 0; i < chains.length; i++) {
            if (chains[i] != currentChainSelector) {
                Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
                    receiver: abi.encode(address(this)),
                    data: encodedMessage,
                    tokenAmounts: new Client.EVMTokenAmount[](0),
                    extraArgs: Client._argsToBytes(Client.EVMExtraArgsV1({gasLimit: 400_000})),
                    feeToken: address(0)
                });
                totalFees += i_router.getFee(chains[i], message);
            }
        }
        return totalFees;
    }

    function supportsInterface(bytes4 interfaceId) public view override(ERC721, CCIPReceiver) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    function getEvent(uint256 eventId) external view returns (Event memory) {
        return events[eventId];
    }

    function hasTicketForEvent(uint256 eventId, address user) external view returns (bool) {
        return hasTicket[eventId][user];
    }

    function getUserTickets(address user) external view returns (uint256[] memory) {
        return userTickets[user];
    }

    function getCurrentChainSelector() external view returns (uint64) {
        return currentChainSelector;
    }

    function estimateEventCreationFees(string memory name, string memory description, uint256 ticketPrice, uint256 totalTickets) external view returns (uint256) {
        return _calculateTotalEventSyncFees(1, msg.sender, name, description, ticketPrice, totalTickets);
    }

    function withdrawFees() external onlyOwner {
        uint256 balance = address(this).balance;
        require(balance > 0, "No fees to withdraw");
        (bool success, ) = owner().call{value: balance}("");
        require(success, "Fee withdrawal failed");
    }

    function setSupportedChain(uint64 chainSelector, bool supported) external onlyOwner {
        supportedChains[chainSelector] = supported;
    }

    receive() external payable {}
}
