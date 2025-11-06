// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {StringUtils} from "@ensdomains/ens-contracts/utils/StringUtils.sol";

import {IL2Registry} from "../interfaces/IL2Registry.sol";
import {IUniversalSignatureValidator} from "../interfaces/IUniversalSignatureValidator.sol";

/// @dev This is an example registrar contract that is mean to be modified.
contract L2Registrar is Ownable {
    using StringUtils for string;
    using MessageHashUtils for bytes32;

    /// @notice Emitted when a new name is registered
    /// @param label The registered label (e.g. "name" in "name.eth")
    /// @param owner The owner of the newly registered name
    event NameRegistered(string indexed label, address indexed owner);

    /// @notice Emitted when an inviter is added
    event InviterAdded(address indexed inviter);

    /// @notice Emitted when an inviter is removed
    event InviterRemoved(address indexed inviter);

    /// @notice Thrown when caller is not authorized
    error Unauthorized();

    /// @notice Thrown when signature has expired
    error SignatureExpired();

    /// @notice Thrown when invite signature has already been used
    error InviteAlreadyUsed();

    /// @notice Thrown when signer is not a whitelisted inviter
    error InvalidInviter();

    /// @notice Reference to the target registry contract
    IL2Registry public immutable registry;

    /// @notice The chainId for the current chain
    uint256 public chainId;

    /// @notice The coinType for the current chain (ENSIP-11)
    uint256 public immutable coinType;

    /// @notice Universal signature validator for verifying invite signatures
    IUniversalSignatureValidator public immutable universalSignatureValidator;

    /// @notice Mapping of whitelisted inviter addresses
    mapping(address => bool) public inviters;

    /// @notice Mapping of used invite signature hashes to prevent replay
    mapping(bytes32 => bool) public usedInvites;

    /// @notice Modifier to check signature expiration
    modifier unexpiredSignature(uint256 expiration) {
        if (block.timestamp > expiration) revert SignatureExpired();
        _;
    }

    /// @notice Initializes the registrar with a registry contract
    /// @param _registry Address of the L2Registry contract
    constructor(address _registry) Ownable(msg.sender) {
        // Save the chainId in memory (can only access this in assembly)
        assembly {
            sstore(chainId.slot, chainid())
        }

        // Calculate the coinType for the current chain according to ENSIP-11
        coinType = (0x80000000 | chainId) >> 0;

        // Save the registry address
        registry = IL2Registry(_registry);

        // Initialize universal signature validator
        universalSignatureValidator = IUniversalSignatureValidator(
            0x164af34fAF9879394370C7f09064127C043A35E9
        );
    }

    /*//////////////////////////////////////////////////////////////
                            ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Adds an address to the inviter whitelist
    /// @param inviter Address to add as an inviter
    function addInviter(address inviter) external onlyOwner {
        inviters[inviter] = true;
        emit InviterAdded(inviter);
    }

    /// @notice Removes an address from the inviter whitelist
    /// @param inviter Address to remove from inviters
    function removeInviter(address inviter) external onlyOwner {
        inviters[inviter] = false;
        emit InviterRemoved(inviter);
    }

    /*//////////////////////////////////////////////////////////////
                        REGISTRATION FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Registers a new name (owner-only, bypasses invite system)
    /// @dev Only contract owner can call this for emergency/admin registrations
    /// @param label The label to register (e.g. "name" for "name.eth")
    /// @param recipient The address that will own the name
    function register(string calldata label, address recipient) external onlyOwner {
        bytes32 node = _labelToNode(label);
        bytes memory addr = abi.encodePacked(recipient); // Convert address to bytes

        // Register the name in the L2 registry first
        registry.createSubnode(
            registry.baseNode(),
            label,
            recipient,
            new bytes[](0)
        );

        // Set the forward address for the current chain (after node creation)
        registry.setAddr(node, coinType, addr);

        // Set the forward address for mainnet ETH (coinType 60)
        registry.setAddr(node, 60, addr);

        emit NameRegistered(label, recipient);
    }

    /// @notice Registers a new name with an invite signature
    /// @param label The label to register (e.g. "name" for "name.eth")
    /// @param recipient The address that will own the name
    /// @param expiration Timestamp when the invite signature expires
    /// @param inviter Address of the inviter who signed the invite
    /// @param signature Signature from the inviter
    function registerWithInvite(
        string calldata label,
        address recipient,
        uint256 expiration,
        address inviter,
        bytes calldata signature
    ) external unexpiredSignature(expiration) {
        // Reconstruct the message hash that was signed
        bytes32 messageHash = keccak256(
            abi.encodePacked(address(this), label, recipient, expiration)
        ).toEthSignedMessageHash();

        // Create a unique invite ID to prevent replay attacks
        bytes32 inviteId = keccak256(
            abi.encodePacked(messageHash, signature)
        );

        // Check if invite has already been used
        if (usedInvites[inviteId]) revert InviteAlreadyUsed();

        // Verify the inviter is whitelisted
        if (!inviters[inviter]) revert InvalidInviter();

        // Verify the signature is valid
        if (!universalSignatureValidator.isValidSig(inviter, messageHash, signature)) {
            revert Unauthorized();
        }

        // If recipient is specified (not zero address), ensure caller is the recipient
        if (recipient != address(0) && msg.sender != recipient) {
            revert Unauthorized();
        }

        // Mark invite as used (before external calls - checks-effects-interactions pattern)
        usedInvites[inviteId] = true;

        bytes32 node = _labelToNode(label);
        bytes memory addr = abi.encodePacked(recipient);

        // Register the name in the L2 registry first
        registry.createSubnode(
            registry.baseNode(),
            label,
            recipient,
            new bytes[](0)
        );

        // Set the forward address for the current chain (after node creation)
        registry.setAddr(node, coinType, addr);

        // Set the forward address for mainnet ETH (coinType 60)
        registry.setAddr(node, 60, addr);

        emit NameRegistered(label, recipient);
    }

    /// @notice Checks if a given label is available for registration
    /// @dev Uses try-catch to handle the ERC721NonexistentToken error
    /// @param label The label to check availability for
    /// @return available True if the label can be registered, false if already taken
    function available(string calldata label) external view returns (bool) {
        bytes32 node = _labelToNode(label);
        uint256 tokenId = uint256(node);

        try registry.ownerOf(tokenId) {
            return false;
        } catch {
            if (label.strlen() >= 3) {
                return true;
            }
            return false;
        }
    }

    function _labelToNode(
        string calldata label
    ) private view returns (bytes32) {
        return registry.makeNode(registry.baseNode(), label);
    }
}
