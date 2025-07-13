// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IAny2EVMMessageReceiver {
  /// @notice Called by the Router to deliver a message. If this reverts, any token transfers also revert.
  /// The message will move to a FAILED state and become available for manual execution.
  /// @param message CCIP Message.
  /// @dev Note ensure you check the msg.sender is the OffRampRouter.
  function ccipReceive(
    Client.Any2EVMMessage calldata message
  ) external;
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

// OpenZeppelin Imports
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

// Chainlink
import {IRouterClient} from "@chainlink/contracts-ccip/contracts/interfaces/IRouterClient.sol";
import {Client} from "@chainlink/contracts-ccip/contracts/libraries/Client.sol";
import {CCIPReceiver} from "@chainlink/contracts-ccip/contracts/applications/CCIPReceiver.sol";

import "@chainlink/contracts/src/v0.8/vrf/VRFConsumerBaseV2.sol";
import "@chainlink/contracts/src/v0.8/automation/interfaces/KeeperCompatibleInterface.sol";
import {VRFCoordinatorV2Interface} from "@chainlink/contracts/src/v0.8/vrf/interfaces/VRFCoordinatorV2Interface.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

/**
 * @title Cross-Chain NFT Ticketing dApp
 * @dev A decentralized ticketing system using Chainlink CCIP for cross-chain communication
 * @dev Supports Ethereum Sepolia, Avalanche Fuji, and Polygon Amoy testnets
 * @dev Events are synchronized across all supported chains
 */
contract CrossChainNFTTicketing is 
    ERC721, 
    IAny2EVMMessageReceiver, 
    OwnerIsCreator, 
    ReentrancyGuard 
{
    // =============================================================================
    // CHAIN SELECTORS (Official Chainlink CCIP Chain Selectors)
    // =============================================================================
    
    // Ethereum Sepolia Testnet
    uint64 public constant SEPOLIA_CHAIN_SELECTOR = 16015286601757825753;
    
    // Avalanche Fuji Testnet  
    uint64 public constant FUJI_CHAIN_SELECTOR = 14767482510784806043;
    
    // Polygon Amoy Testnet
    uint64 public constant AMOY_CHAIN_SELECTOR = 16281711391670634445;

    // =============================================================================
    // MESSAGE TYPES
    // =============================================================================
    
    enum MessageType {
        EVENT_CREATION,
        TICKET_PURCHASE,
        TICKET_SOLD_UPDATE
    }

    // =============================================================================
    // STATE VARIABLES
    // =============================================================================
    
    IRouterClient private immutable ccipRouter;
    uint64 private immutable currentChainSelector;
    
    uint256 private _eventIdCounter;
    uint256 private _ticketIdCounter;

    // =============================================================================
    // STRUCTS
    // =============================================================================
    
    /**
     * @dev Event structure containing all event details
     */
    struct Event {
        uint256 eventId;
        address organizer;
        string name;
        string description;
        uint256 ticketPrice;
        uint64 originChainSelector;  // Chain where event was originally created
        uint64 nftChainSelector;     // Chain where NFTs will be minted
        uint256 totalTickets;
        uint256 soldTickets;
        bool isActive;
        bool exists;  // Flag to check if event exists
    }

    /**
     * @dev Event creation message structure for CCIP communication
     */
    struct EventCreationMessage {
        uint256 eventId;
        address organizer;
        string name;
        string description;
        uint256 ticketPrice;
        uint64 originChainSelector;
        uint64 nftChainSelector;
        uint256 totalTickets;
        uint256 timestamp;
    }

    /**
     * @dev Ticket message structure for CCIP communication
     */
    struct TicketMessage {
        uint256 eventId;
        address buyer;
        string ticketType;
        uint256 timestamp;
    }

    /**
     * @dev Ticket sold update message structure
     */
    struct TicketSoldUpdateMessage {
        uint256 eventId;
        uint256 newSoldCount;
        uint256 timestamp;
    }

    /**
     * @dev Generic CCIP message wrapper
     */
    struct CCIPMessage {
        MessageType messageType;
        bytes data;
    }

    // =============================================================================
    // MAPPINGS
    // =============================================================================
    
    // eventId => Event details
    mapping(uint256 => Event) public events;
    
    // eventId => buyer => hasTicket
    mapping(uint256 => mapping(address => bool)) public hasTicket;
    
    // buyer => eventId[]
    mapping(address => uint256[]) public userTickets;
    
    // ticketId => eventId
    mapping(uint256 => uint256) public ticketToEvent;
    
    // Chain selector => supported chain
    mapping(uint64 => bool) public supportedChains;
    
    // Global event ID counter across all chains
    mapping(uint256 => bool) public eventIdExists;

    // =============================================================================
    // EVENTS
    // =============================================================================
    
    event EventListed(
        uint256 indexed eventId,
        address indexed organizer,
        string name,
        uint256 ticketPrice,
        uint64 originChainSelector,
        uint64 nftChainSelector
    );
    
    event EventSynced(
        uint256 indexed eventId,
        uint64 indexed fromChain,
        string name
    );
    
    event TicketPurchased(
        uint256 indexed eventId,
        address indexed buyer,
        uint256 amount,
        uint64 destinationChain
    );
    
    event TicketMinted(
        uint256 indexed eventId,
        address indexed buyer,
        uint256 indexed ticketId
    );
    
    event TicketSoldCountUpdated(
        uint256 indexed eventId,
        uint256 newSoldCount,
        uint64 indexed fromChain
    );
    
    event CCIPMessageSent(
        bytes32 indexed messageId,
        uint64 indexed destinationChain,
        MessageType indexed messageType,
        uint256 eventId
    );
    
    event CCIPMessageReceived(
        bytes32 indexed messageId,
        uint64 indexed sourceChain,
        MessageType indexed messageType,
        uint256 eventId
    );

    // =============================================================================
    // MODIFIERS
    // =============================================================================
    
    /**
     * @dev Restricts access to CCIP Router only
     */
    modifier onlyRouter() {
        require(msg.sender == address(ccipRouter), "Only CCIP Router can call");
        _;
    }
    
    /**
     * @dev Checks if chain is supported
     */
    modifier onlySupportedChain(uint64 chainSelector) {
        require(supportedChains[chainSelector], "Chain not supported");
        _;
    }

    /**
     * @dev Checks if event exists
     */
    modifier eventExists(uint256 _eventId) {
        require(events[_eventId].exists, "Event does not exist");
        _;
    }

    // =============================================================================
    // CONSTRUCTOR
    // =============================================================================
    
    /**
     * @dev Constructor initializes the contract with CCIP router
     * @param _ccipRouter Address of the CCIP Router contract
     * @param _currentChainSelector Chain selector for the current deployment
     */
    constructor(
        address _ccipRouter,
        uint64 _currentChainSelector
    ) ERC721("CrossChainTicket", "CCT") {
        ccipRouter = IRouterClient(_ccipRouter);
        currentChainSelector = _currentChainSelector;
        
        // Initialize counters
        _eventIdCounter = 0;
        _ticketIdCounter = 0;
        
        // Initialize supported chains
        supportedChains[SEPOLIA_CHAIN_SELECTOR] = true;
        supportedChains[FUJI_CHAIN_SELECTOR] = true;
        supportedChains[AMOY_CHAIN_SELECTOR] = true;
    }

    // =============================================================================
    // EVENT MANAGEMENT FUNCTIONS
    // =============================================================================
    
    /**
     * @dev Allows event organizer to deactivate their event
     * @param _eventId Event ID to deactivate
     */
    function deactivateEvent(uint256 _eventId) external eventExists(_eventId) {
        Event storage eventDetails = events[_eventId];
        require(eventDetails.organizer == msg.sender, "Only organizer can deactivate event");
        require(eventDetails.isActive, "Event is already inactive");
        
        eventDetails.isActive = false;
    }

    /**
     * @dev Emergency function to deactivate any event (owner only)
     * @param _eventId Event ID to deactivate
     */
    function emergencyDeactivateEvent(uint256 _eventId) external onlyOwner eventExists(_eventId) {
        events[_eventId].isActive = false;
    }
    
    /**
     * @dev Internal function to check if a token exists
     * @param tokenId Token ID to check
     * @return bool indicating if token exists
     */
    function _exists(uint256 tokenId) internal view returns (bool) {
        return _ownerOf(tokenId) != address(0);
    }

    /**
     * @dev Returns token URI for NFT (can be overridden for custom metadata)
     * @param _tokenId Token ID
     * @return Token URI
     */
    function tokenURI(uint256 _tokenId) public view override returns (string memory) {
        require(_exists(_tokenId), "Token does not exist");
        
        uint256 eventId = ticketToEvent[_tokenId];
        Event memory eventDetails = events[eventId];
        
        // Basic metadata - can be enhanced with actual metadata service
        return string(abi.encodePacked(
            "data:application/json;base64,",
            Base64.encode(bytes(abi.encodePacked(
                '{"name":"',
                eventDetails.name,
                ' Ticket #',
                Strings.toString(_tokenId),
                '","description":"',
                eventDetails.description,
                '","attributes":[{"trait_type":"Event ID","value":"',
                Strings.toString(eventId),
                '"},{"trait_type":"Origin Chain","value":"',
                Strings.toString(eventDetails.originChainSelector),
                '"},{"trait_type":"NFT Chain","value":"',
                Strings.toString(eventDetails.nftChainSelector),
                '"},{"trait_type":"Organizer","value":"',
                Strings.toHexString(uint160(eventDetails.organizer), 20),
                '"}]}'
            )))
        ));
    }

    function addEvent(
        string memory _name,
        string memory _description,
        uint256 _ticketPrice,
        uint256 _totalTickets,
        uint64 _nftChainSelector
    ) external payable onlySupportedChain(_nftChainSelector) {
        require(_ticketPrice > 0, "Ticket price must be greater than 0");
        require(_totalTickets > 0, "Total tickets must be greater than 0");
        require(bytes(_name).length > 0, "Event name cannot be empty");
        
        _eventIdCounter++;
        uint256 eventId = _eventIdCounter;
        
        // Create event locally
        _createEventLocally(
            eventId,
            msg.sender,
            _name,
            _description,
            _ticketPrice,
            currentChainSelector,
            _nftChainSelector,
            _totalTickets
        );
        
        // Sync event to all other supported chains
        _syncEventToAllChains(
            eventId,
            msg.sender,
            _name,
            _description,
            _ticketPrice,
            _nftChainSelector,
            _totalTickets
        );
        
        emit EventListed(eventId, msg.sender, _name, _ticketPrice, currentChainSelector, _nftChainSelector);
    }

    /**
     * @dev Creates event locally without CCIP sync
     */
    function _createEventLocally(
        uint256 _eventId,
        address _organizer,
        string memory _name,
        string memory _description,
        uint256 _ticketPrice,
        uint64 _originChainSelector,
        uint64 _nftChainSelector,
        uint256 _totalTickets
    ) internal {
        events[_eventId] = Event({
            eventId: _eventId,
            organizer: _organizer,
            name: _name,
            description: _description,
            ticketPrice: _ticketPrice,
            originChainSelector: _originChainSelector,
            nftChainSelector: _nftChainSelector,
            totalTickets: _totalTickets,
            soldTickets: 0,
            isActive: true,
            exists: true
        });
        
        eventIdExists[_eventId] = true;
    }

    /**
     * @dev Syncs event creation to all other supported chains
     */
    function _syncEventToAllChains(
        uint256 _eventId,
        address _organizer,
        string memory _name,
        string memory _description,
        uint256 _ticketPrice,
        uint64 _nftChainSelector,
        uint256 _totalTickets
    ) internal {
        // Get all supported chain selectors
        uint64[] memory chains = _getSupportedChains();
        
        // Calculate total CCIP fees needed
        uint256 totalFees = _calculateTotalCCIPFees(_eventId, _organizer, _name, _description, _ticketPrice, _nftChainSelector, _totalTickets, chains);
        require(msg.value >= totalFees, "Insufficient CCIP fees");
        
        // Send to each chain (except current chain)
        for (uint256 i = 0; i < chains.length; i++) {
            if (chains[i] != currentChainSelector) {
                _sendEventCreationMessage(
                    _eventId,
                    _organizer,
                    _name,
                    _description,
                    _ticketPrice,
                    _nftChainSelector,
                    _totalTickets,
                    chains[i]
                );
            }
        }
    }

    /**
     * @dev Sends event creation message to specific chain
     */
    function _sendEventCreationMessage(
        uint256 _eventId,
        address _organizer,
        string memory _name,
        string memory _description,
        uint256 _ticketPrice,
        uint64 _nftChainSelector,
        uint256 _totalTickets,
        uint64 _destinationChain
    ) internal {
        // Create event creation message
        EventCreationMessage memory eventMsg = EventCreationMessage({
            eventId: _eventId,
            organizer: _organizer,
            name: _name,
            description: _description,
            ticketPrice: _ticketPrice,
            originChainSelector: currentChainSelector,
            nftChainSelector: _nftChainSelector,
            totalTickets: _totalTickets,
            timestamp: block.timestamp
        });
        
        // Wrap in generic CCIP message
        CCIPMessage memory ccipMsg = CCIPMessage({
            messageType: MessageType.EVENT_CREATION,
            data: abi.encode(eventMsg)
        });
        
        // Send CCIP message
        _sendCCIPMessage(ccipMsg, _destinationChain, _eventId);
    }

    // =============================================================================
    // TICKET PURCHASE FUNCTIONS
    // =============================================================================
    
    /**
     * @dev Allows users to buy tickets from any supported chain
     * @param _eventId ID of the event
     * @param _ticketType Type of ticket (e.g., "General", "VIP")
     */
    function buyTicket(
        uint256 _eventId,
        string memory _ticketType
    ) external payable nonReentrant eventExists(_eventId) {
        Event storage eventDetails = events[_eventId];
        require(eventDetails.isActive, "Event is not active");
        require(eventDetails.soldTickets < eventDetails.totalTickets, "Event sold out");
        require(msg.value >= eventDetails.ticketPrice, "Insufficient payment");
        require(!hasTicket[_eventId][msg.sender], "Already has ticket for this event");
        
        // Transfer payment to organizer on current chain
        (bool success, ) = eventDetails.organizer.call{value: eventDetails.ticketPrice}("");
        require(success, "Payment transfer failed");
        
        // If buying on the same chain where NFTs will be minted, mint directly
        if (currentChainSelector == eventDetails.nftChainSelector) {
            _mintTicket(_eventId, msg.sender, _ticketType);
        } else {
            // Send CCIP message to destination chain for minting
            _sendTicketPurchaseMessage(_eventId, msg.sender, _ticketType, eventDetails.nftChainSelector);
        }
        
        // Update sold tickets count and sync to origin chain if different
        eventDetails.soldTickets++;
        if (currentChainSelector != eventDetails.originChainSelector) {
            _sendTicketSoldUpdateMessage(_eventId, eventDetails.soldTickets, eventDetails.originChainSelector);
        }
        
        emit TicketPurchased(_eventId, msg.sender, eventDetails.ticketPrice, eventDetails.nftChainSelector);
    }

    /**
     * @dev Sends ticket purchase message to NFT minting chain
     */
    function _sendTicketPurchaseMessage(
        uint256 _eventId,
        address _buyer,
        string memory _ticketType,
        uint64 _destinationChain
    ) internal {
        // Create ticket message
        TicketMessage memory ticketMsg = TicketMessage({
            eventId: _eventId,
            buyer: _buyer,
            ticketType: _ticketType,
            timestamp: block.timestamp
        });
        
        // Wrap in generic CCIP message
        CCIPMessage memory ccipMsg = CCIPMessage({
            messageType: MessageType.TICKET_PURCHASE,
            data: abi.encode(ticketMsg)
        });
        
        // Send CCIP message
        _sendCCIPMessage(ccipMsg, _destinationChain, _eventId);
    }

    /**
     * @dev Sends ticket sold count update to origin chain
     */
    function _sendTicketSoldUpdateMessage(
        uint256 _eventId,
        uint256 _newSoldCount,
        uint64 _destinationChain
    ) internal {
        // Create ticket sold update message
        TicketSoldUpdateMessage memory updateMsg = TicketSoldUpdateMessage({
            eventId: _eventId,
            newSoldCount: _newSoldCount,
            timestamp: block.timestamp
        });
        
        // Wrap in generic CCIP message
        CCIPMessage memory ccipMsg = CCIPMessage({
            messageType: MessageType.TICKET_SOLD_UPDATE,
            data: abi.encode(updateMsg)
        });
        
        // Send CCIP message
        _sendCCIPMessage(ccipMsg, _destinationChain, _eventId);
    }

    // =============================================================================
    // CCIP FUNCTIONS
    // =============================================================================
    
    /**
     * @dev Generic CCIP message sender
     */
    function _sendCCIPMessage(
        CCIPMessage memory _ccipMsg,
        uint64 _destinationChain,
        uint256 _eventId
    ) internal {
        // Encode message
        bytes memory encodedMessage = abi.encode(_ccipMsg);
        
        // Create CCIP message
        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(address(this)), // Send to same contract on destination chain
            data: encodedMessage,
            tokenAmounts: new Client.EVMTokenAmount[](0), // No tokens being sent
            extraArgs: Client._argsToBytes(
                Client.EVMExtraArgsV1({gasLimit: 500_000}) // Increased gas limit for complex operations
            ),
            feeToken: address(0) // Pay fees in native token
        });
        
        // Calculate and pay CCIP fees
        uint256 ccipFee = ccipRouter.getFee(_destinationChain, message);
        require(address(this).balance >= ccipFee, "Insufficient balance for CCIP fees");
        
        // Send message
        bytes32 messageId = ccipRouter.ccipSend{value: ccipFee}(_destinationChain, message);
        
        emit CCIPMessageSent(messageId, _destinationChain, _ccipMsg.messageType, _eventId);
    }
    
    /**
     * @dev Receives and processes CCIP messages
     * @param message CCIP message received
     */
    function ccipReceive(
        Client.Any2EVMMessage calldata message
    ) external override onlyRouter {
        // Decode the generic CCIP message
        CCIPMessage memory ccipMsg = abi.decode(message.data, (CCIPMessage));
        
        // Process based on message type
        if (ccipMsg.messageType == MessageType.EVENT_CREATION) {
            _handleEventCreationMessage(ccipMsg.data, message.sourceChainSelector, message.messageId);
        } else if (ccipMsg.messageType == MessageType.TICKET_PURCHASE) {
            _handleTicketPurchaseMessage(ccipMsg.data, message.sourceChainSelector, message.messageId);
        } else if (ccipMsg.messageType == MessageType.TICKET_SOLD_UPDATE) {
            _handleTicketSoldUpdateMessage(ccipMsg.data, message.sourceChainSelector, message.messageId);
        }
    }

    /**
     * @dev Handles event creation messages from other chains
     */
    function _handleEventCreationMessage(
        bytes memory _data,
        uint64 _sourceChain,
        bytes32 _messageId
    ) internal {
        EventCreationMessage memory eventMsg = abi.decode(_data, (EventCreationMessage));
        
        // Only create if event doesn't already exist
        if (!events[eventMsg.eventId].exists) {
            _createEventLocally(
                eventMsg.eventId,
                eventMsg.organizer,
                eventMsg.name,
                eventMsg.description,
                eventMsg.ticketPrice,
                eventMsg.originChainSelector,
                eventMsg.nftChainSelector,
                eventMsg.totalTickets
            );
            
            emit EventSynced(eventMsg.eventId, _sourceChain, eventMsg.name);
        }
        
        emit CCIPMessageReceived(_messageId, _sourceChain, MessageType.EVENT_CREATION, eventMsg.eventId);
    }

    /**
     * @dev Handles ticket purchase messages from other chains
     */
    function _handleTicketPurchaseMessage(
        bytes memory _data,
        uint64 _sourceChain,
        bytes32 _messageId
    ) internal {
        TicketMessage memory ticketMsg = abi.decode(_data, (TicketMessage));
        
        // Mint ticket for the buyer
        _mintTicket(ticketMsg.eventId, ticketMsg.buyer, ticketMsg.ticketType);
        
        emit CCIPMessageReceived(_messageId, _sourceChain, MessageType.TICKET_PURCHASE, ticketMsg.eventId);
    }

    /**
     * @dev Handles ticket sold count update messages
     */
    function _handleTicketSoldUpdateMessage(
        bytes memory _data,
        uint64 _sourceChain,
        bytes32 _messageId
    ) internal {
        TicketSoldUpdateMessage memory updateMsg = abi.decode(_data, (TicketSoldUpdateMessage));
        
        // Update sold tickets count if event exists
        if (events[updateMsg.eventId].exists) {
            events[updateMsg.eventId].soldTickets = updateMsg.newSoldCount;
            emit TicketSoldCountUpdated(updateMsg.eventId, updateMsg.newSoldCount, _sourceChain);
        }
        
        emit CCIPMessageReceived(_messageId, _sourceChain, MessageType.TICKET_SOLD_UPDATE, updateMsg.eventId);
    }

    // =============================================================================
    // NFT MINTING FUNCTIONS
    // =============================================================================
    
    /**
     * @dev Mints NFT ticket for buyer
     * @param _eventId Event ID
     * @param _buyer Buyer address
     * @param _ticketType Type of ticket
     */
    function _mintTicket(
        uint256 _eventId,
        address _buyer,
        string memory _ticketType
    ) internal {
        Event storage eventDetails = events[_eventId];
        require(eventDetails.exists, "Event does not exist");
        require(eventDetails.isActive, "Event is not active");
        require(eventDetails.soldTickets < eventDetails.totalTickets, "Event sold out");
        require(!hasTicket[_eventId][_buyer], "Already has ticket for this event");
        
        // Increment ticket counter
        _ticketIdCounter++;
        uint256 ticketId = _ticketIdCounter;
        
        // Update mappings
        hasTicket[_eventId][_buyer] = true;
        userTickets[_buyer].push(_eventId);
        ticketToEvent[ticketId] = _eventId;
        
        // Mint NFT
        _safeMint(_buyer, ticketId);
        
        emit TicketMinted(_eventId, _buyer, ticketId);
    }

    // =============================================================================
    // UTILITY FUNCTIONS
    // =============================================================================
    
    /**
     * @dev Returns array of supported chain selectors
     */
    function _getSupportedChains() internal pure returns (uint64[] memory) {
        uint64[] memory chains = new uint64[](3);
        chains[0] = SEPOLIA_CHAIN_SELECTOR;
        chains[1] = FUJI_CHAIN_SELECTOR;
        chains[2] = AMOY_CHAIN_SELECTOR;
        return chains;
    }

    /**
     * @dev Calculates total CCIP fees for event creation sync
     */
    function _calculateTotalCCIPFees(
        uint256 _eventId,
        address _organizer,
        string memory _name,
        string memory _description,
        uint256 _ticketPrice,
        uint64 _nftChainSelector,
        uint256 _totalTickets,
        uint64[] memory _chains
    ) internal view returns (uint256) {
        uint256 totalFees = 0;
        
        // Create sample message for fee calculation
        EventCreationMessage memory eventMsg = EventCreationMessage({
            eventId: _eventId,
            organizer: _organizer,
            name: _name,
            description: _description,
            ticketPrice: _ticketPrice,
            originChainSelector: currentChainSelector,
            nftChainSelector: _nftChainSelector,
            totalTickets: _totalTickets,
            timestamp: block.timestamp
        });
        
        CCIPMessage memory ccipMsg = CCIPMessage({
            messageType: MessageType.EVENT_CREATION,
            data: abi.encode(eventMsg)
        });
        
        bytes memory encodedMessage = abi.encode(ccipMsg);
        
        // Calculate fees for each destination chain
        for (uint256 i = 0; i < _chains.length; i++) {
            if (_chains[i] != currentChainSelector) {
                Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
                    receiver: abi.encode(address(this)),
                    data: encodedMessage,
                    tokenAmounts: new Client.EVMTokenAmount[](0),
                    extraArgs: Client._argsToBytes(
                        Client.EVMExtraArgsV1({gasLimit: 500_000})
                    ),
                    feeToken: address(0)
                });
                
                totalFees += ccipRouter.getFee(_chains[i], message);
            }
        }
        
        return totalFees;
    }

    /**
     * @dev Estimates CCIP fees for event creation
     */
    function estimateEventCreationFees(
        string memory _name,
        string memory _description,
        uint256 _ticketPrice,
        uint64 _nftChainSelector,
        uint256 _totalTickets
    ) external view returns (uint256) {
        uint64[] memory chains = _getSupportedChains();
        return _calculateTotalCCIPFees(
            1, // Sample event ID
            msg.sender,
            _name,
            _description,
            _ticketPrice,
            _nftChainSelector,
            _totalTickets,
            chains
        );
    }

    // =============================================================================
    // VIEW FUNCTIONS
    // =============================================================================
    
    /**
     * @dev Returns event details
     * @param _eventId Event ID
     * @return Event details
     */
    function getEvent(uint256 _eventId) external view returns (Event memory) {
        return events[_eventId];
    }
    
    /**
     * @dev Checks if user has ticket for specific event
     * @param _eventId Event ID
     * @param _user User address
     * @return bool indicating if user has ticket
     */
    function hasTicketForEvent(uint256 _eventId, address _user) external view returns (bool) {
        return hasTicket[_eventId][_user];
    }
    
    /**
     * @dev Returns all event IDs for which user has tickets
     * @param _user User address
     * @return Array of event IDs
     */
    function getUserTickets(address _user) external view returns (uint256[] memory) {
        return userTickets[_user];
    }
    
    /**
     * @dev Returns current chain selector
     * @return Current chain selector
     */
    function getCurrentChainSelector() external view returns (uint64) {
        return currentChainSelector;
    }
    
    /**
     * @dev Returns CCIP router address
     * @return CCIP router address
     */
    function getCCIPRouter() external view returns (address) {
        return address(ccipRouter);
    }
    
    /**
     * @dev Returns total number of events created
     * @return Total events count
     */
    function getTotalEvents() external view returns (uint256) {
        return _eventIdCounter;
    }
    
    /**
     * @dev Returns total number of tickets minted
     * @return Total tickets count
     */
    function getTotalTickets() external view returns (uint256) {
        return _ticketIdCounter;
    }

    /**
     * @dev Returns all active events
     * @return Array of event IDs
     */
    function getAllActiveEvents() external view returns (uint256[] memory) {
        uint256 activeCount = 0;
        
        // Count active events
        for (uint256 i = 1; i <= _eventIdCounter; i++) {
            if (events[i].exists && events[i].isActive) {
                activeCount++;
            }
        }
        
        // Create array of active event IDs
        uint256[] memory activeEvents = new uint256[](activeCount);
        uint256 index = 0;
        
        for (uint256 i = 1; i <= _eventIdCounter; i++) {
            if (events[i].exists && events[i].isActive) {
                activeEvents[index] = i;
                index++;
            }
        }
        
        return activeEvents;
    }

    // =============================================================================
    // ADMIN FUNCTIONS
    // =============================================================================
    
    /**
     * @dev Allows contract owner to withdraw accumulated fees
     */
    function withdrawFees() external onlyOwner {
        uint256 balance = address(this).balance;
        require(balance > 0, "No fees to withdraw");
        
        (bool success, ) = owner().call{value: balance}("");
        require(success, "Fee withdrawal failed");
    }
    
    /**
     * @dev Allows contract owner to add/remove supported chains
     * @param _chainSelector Chain selector
     * @param _supported Whether chain is supported
     */
    function setSupportedChain(uint64 _chainSelector, bool _supported) external onlyOwner {
        supportedChains[_chainSelector] = _supported;
    }

    /**
     * @dev Allows contract to receive native tokens for CCIP fees
     */
    receive() external payable {}
    
    /**
     * @dev Fallback function
     */
    fallback() external payable {}
}

// =============================================================================
// UTILITY LIBRARIES
// =============================================================================

library Base64 {
    string internal constant TABLE = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    
    function encode(bytes memory data) internal pure returns (string memory) {
        if (data.length == 0) return "";
        
        string memory table = TABLE;
        uint256 encodedLen = 4 * ((data.length + 2) / 3);
        string memory result = new string(encodedLen + 32);
        
        assembly {
            mstore(result, encodedLen)
            let tablePtr := add(table, 1)
            let dataPtr := data
            let endPtr := add(dataPtr, mload(data))
            let resultPtr := add(result, 32)
            
            for {} lt(dataPtr, endPtr) {}
            {
                dataPtr := add(dataPtr, 3)
                let input := mload(dataPtr)
                
                mstore(resultPtr, shl(248, mload(add(tablePtr, and(shr(18, input), 0x3F)))))
                resultPtr := add(resultPtr, 1)
                mstore(resultPtr, shl(248, mload(add(tablePtr, and(shr(12, input), 0x3F)))))
                resultPtr := add(resultPtr, 1)
                mstore(resultPtr, shl(248, mload(add(tablePtr, and(shr(6, input), 0x3F)))))
                resultPtr := add(resultPtr, 1)
                mstore(resultPtr, shl(248, mload(add(tablePtr, and(input, 0x3F)))))
                resultPtr := add(resultPtr, 1)
            }
            
            switch mod(mload(data), 3)
            case 1 { mstore(sub(resultPtr, 2), shl(240, 0x3d3d)) }
            case 2 { mstore(sub(resultPtr, 1), shl(248, 0x3d)) }
        }
        
        return result;
    }
}