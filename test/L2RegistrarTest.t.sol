// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {L2Registrar} from "../src/examples/L2Registrar.sol";
import {L2Registry} from "../src/L2Registry.sol";
import {L2RegistryFactory} from "../src/L2RegistryFactory.sol";

contract L2RegistrarTest is Test, IERC721Receiver {
    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) external pure override returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }
    L2Registrar public registrar;
    L2Registry public registry;
    L2RegistryFactory public factory;

    address public owner;
    address public inviter;
    address public recipient;
    address public attacker;

    bytes32 public baseNode;

    function setUp() public {
        owner = address(this);
        inviter = makeAddr("inviter");
        recipient = makeAddr("recipient");
        attacker = makeAddr("attacker");

        // Deploy implementation and factory
        L2Registry implementation = new L2Registry();
        factory = new L2RegistryFactory(address(implementation));

        // Deploy registry
        address registryAddr = factory.deployRegistry(
            "osopit.eth",
            "OSOPIT",
            "https://osopit.com/metadata/",
            owner
        );
        registry = L2Registry(registryAddr);

        baseNode = registry.baseNode();

        // Deploy registrar
        registrar = new L2Registrar(address(registry));

        // Add registrar to registry
        registry.addRegistrar(address(registrar));

        // Add inviter
        registrar.addInviter(inviter);
    }

    /*//////////////////////////////////////////////////////////////
                        DEPLOYMENT & SETUP TESTS
    //////////////////////////////////////////////////////////////*/

    function test_DeploymentState() public {
        assertEq(address(registrar.registry()), address(registry));
        assertEq(registrar.owner(), owner);
        assertEq(registrar.chainId(), block.chainid);

        // CoinType should be (0x80000000 | chainId) >> 0
        uint256 expectedCoinType = (0x80000000 | block.chainid) >> 0;
        assertEq(registrar.coinType(), expectedCoinType);
    }

    function test_UniversalSignatureValidatorSet() public {
        address validator = address(registrar.universalSignatureValidator());
        assertEq(validator, 0x164af34fAF9879394370C7f09064127C043A35E9);
    }

    /*//////////////////////////////////////////////////////////////
                        ADMIN FUNCTION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_AddInviter() public {
        address newInviter = makeAddr("newInviter");

        vm.expectEmit(true, false, false, false);
        emit L2Registrar.InviterAdded(newInviter);

        registrar.addInviter(newInviter);

        assertTrue(registrar.inviters(newInviter));
    }

    function test_AddInviterRevertsForNonOwner() public {
        address newInviter = makeAddr("newInviter");

        vm.prank(attacker);
        vm.expectRevert();
        registrar.addInviter(newInviter);
    }

    function test_RemoveInviter() public {
        vm.expectEmit(true, false, false, false);
        emit L2Registrar.InviterRemoved(inviter);

        registrar.removeInviter(inviter);

        assertFalse(registrar.inviters(inviter));
    }

    function test_RemoveInviterRevertsForNonOwner() public {
        vm.prank(attacker);
        vm.expectRevert();
        registrar.removeInviter(inviter);
    }

    /*//////////////////////////////////////////////////////////////
                    OWNER-ONLY REGISTER TESTS
    //////////////////////////////////////////////////////////////*/

    function test_RegisterByOwner() public {
        string memory label = "alice";

        vm.expectEmit(false, false, false, true);
        emit L2Registrar.NameRegistered(label, recipient);

        registrar.register(label, recipient);

        // Verify name was registered
        bytes32 node = registry.makeNode(baseNode, label);
        assertEq(registry.ownerOf(uint256(node)), recipient);

        // Verify addresses were set
        bytes memory addr = abi.encodePacked(recipient);
        assertEq(registry.addr(node, registrar.coinType()), addr);
        assertEq(registry.addr(node, 60), addr);
    }

    function test_RegisterRevertsForNonOwner() public {
        vm.prank(attacker);
        vm.expectRevert();
        registrar.register("alice", recipient);
    }

    function test_RegisterTwiceReverts() public {
        string memory label = "alice";

        registrar.register(label, recipient);

        // Try to register again
        vm.expectRevert();
        registrar.register(label, recipient);
    }

    /*//////////////////////////////////////////////////////////////
                REGISTER WITH INVITE - SUCCESS CASES
    //////////////////////////////////////////////////////////////*/

    function test_RegisterWithInviteSuccess() public {
        string memory label = "bob";
        uint256 expiration = block.timestamp + 1 days;

        // Create signature
        bytes32 messageHash = keccak256(
            abi.encodePacked(address(registrar), label, recipient, expiration)
        );
        bytes32 ethSignedMessageHash = keccak256(
            abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash)
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            uint256(keccak256(abi.encodePacked("inviter"))),
            ethSignedMessageHash
        );
        bytes memory signature = abi.encodePacked(r, s, v);

        // Register with invite as recipient
        vm.prank(recipient);
        registrar.registerWithInvite(label, recipient, expiration, inviter, signature);

        // Verify registration
        bytes32 node = registry.makeNode(baseNode, label);
        assertEq(registry.ownerOf(uint256(node)), recipient);
    }

    function test_RegisterWithInviteOpenRecipient() public {
        string memory label = "charlie";
        uint256 expiration = block.timestamp + 1 days;
        address zeroAddress = address(0);

        // Create signature with zero address (open invite)
        bytes32 messageHash = keccak256(
            abi.encodePacked(address(registrar), label, zeroAddress, expiration)
        );
        bytes32 ethSignedMessageHash = keccak256(
            abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash)
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            uint256(keccak256(abi.encodePacked("inviter"))),
            ethSignedMessageHash
        );
        bytes memory signature = abi.encodePacked(r, s, v);

        // Anyone can use this invite
        address randomUser = makeAddr("randomUser");
        vm.prank(randomUser);
        registrar.registerWithInvite(label, zeroAddress, expiration, inviter, signature);

        // Verify registration (should be to zero address as specified)
        bytes32 node = registry.makeNode(baseNode, label);
        assertEq(registry.ownerOf(uint256(node)), zeroAddress);
    }

    /*//////////////////////////////////////////////////////////////
            REGISTER WITH INVITE - SECURITY TESTS
    //////////////////////////////////////////////////////////////*/

    function test_RegisterWithInviteRevertsExpired() public {
        string memory label = "expired";
        uint256 expiration = block.timestamp - 1; // Expired

        bytes32 messageHash = keccak256(
            abi.encodePacked(address(registrar), label, recipient, expiration)
        );
        bytes32 ethSignedMessageHash = keccak256(
            abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash)
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            uint256(keccak256(abi.encodePacked("inviter"))),
            ethSignedMessageHash
        );
        bytes memory signature = abi.encodePacked(r, s, v);

        vm.prank(recipient);
        vm.expectRevert(L2Registrar.SignatureExpired.selector);
        registrar.registerWithInvite(label, recipient, expiration, inviter, signature);
    }

    function test_RegisterWithInviteRevertsAlreadyUsed() public {
        string memory label = "reuse";
        uint256 expiration = block.timestamp + 1 days;

        bytes32 messageHash = keccak256(
            abi.encodePacked(address(registrar), label, recipient, expiration)
        );
        bytes32 ethSignedMessageHash = keccak256(
            abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash)
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            uint256(keccak256(abi.encodePacked("inviter"))),
            ethSignedMessageHash
        );
        bytes memory signature = abi.encodePacked(r, s, v);

        // Use invite first time
        vm.prank(recipient);
        registrar.registerWithInvite(label, recipient, expiration, inviter, signature);

        // Try to use again
        vm.prank(recipient);
        vm.expectRevert(L2Registrar.InviteAlreadyUsed.selector);
        registrar.registerWithInvite(label, recipient, expiration, inviter, signature);
    }

    function test_RegisterWithInviteRevertsInvalidInviter() public {
        string memory label = "notinviter";
        uint256 expiration = block.timestamp + 1 days;
        address notInviter = makeAddr("notInviter");

        bytes32 messageHash = keccak256(
            abi.encodePacked(address(registrar), label, recipient, expiration)
        );
        bytes32 ethSignedMessageHash = keccak256(
            abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash)
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            uint256(keccak256(abi.encodePacked("notInviter"))),
            ethSignedMessageHash
        );
        bytes memory signature = abi.encodePacked(r, s, v);

        vm.prank(recipient);
        vm.expectRevert(L2Registrar.InvalidInviter.selector);
        registrar.registerWithInvite(label, recipient, expiration, notInviter, signature);
    }

    function test_RegisterWithInviteRevertsWrongRecipient() public {
        string memory label = "wrongrecipient";
        uint256 expiration = block.timestamp + 1 days;

        // Signature is for 'recipient' but attacker tries to use it
        bytes32 messageHash = keccak256(
            abi.encodePacked(address(registrar), label, recipient, expiration)
        );
        bytes32 ethSignedMessageHash = keccak256(
            abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash)
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            uint256(keccak256(abi.encodePacked("inviter"))),
            ethSignedMessageHash
        );
        bytes memory signature = abi.encodePacked(r, s, v);

        // Attacker tries to use invite meant for recipient
        vm.prank(attacker);
        vm.expectRevert(L2Registrar.Unauthorized.selector);
        registrar.registerWithInvite(label, recipient, expiration, inviter, signature);
    }

    function test_RegisterWithInviteRevertsInvalidSignature() public {
        string memory label = "badsig";
        uint256 expiration = block.timestamp + 1 days;

        // Create signature with wrong message
        bytes32 wrongMessageHash = keccak256(
            abi.encodePacked(address(registrar), "wronglabel", recipient, expiration)
        );
        bytes32 ethSignedMessageHash = keccak256(
            abi.encodePacked("\x19Ethereum Signed Message:\n32", wrongMessageHash)
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            uint256(keccak256(abi.encodePacked("inviter"))),
            ethSignedMessageHash
        );
        bytes memory signature = abi.encodePacked(r, s, v);

        vm.prank(recipient);
        vm.expectRevert(L2Registrar.Unauthorized.selector);
        registrar.registerWithInvite(label, recipient, expiration, inviter, signature);
    }

    /*//////////////////////////////////////////////////////////////
                        UTILITY FUNCTION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Available() public {
        string memory label = "available";

        // Should be available before registration
        assertTrue(registrar.available(label));

        // Register
        registrar.register(label, recipient);

        // Should not be available after registration
        assertFalse(registrar.available(label));
    }

    function test_AvailableShortLabel() public {
        // Labels < 3 chars should not be available
        assertFalse(registrar.available("ab"));
        assertFalse(registrar.available("a"));
        assertFalse(registrar.available(""));
    }

    /*//////////////////////////////////////////////////////////////
                        OWNABLE FUNCTIONALITY
    //////////////////////////////////////////////////////////////*/

    function test_TransferOwnership() public {
        address newOwner = makeAddr("newOwner");

        registrar.transferOwnership(newOwner);

        assertEq(registrar.owner(), newOwner);
    }

    function test_TransferOwnershipRevertsForNonOwner() public {
        address newOwner = makeAddr("newOwner");

        vm.prank(attacker);
        vm.expectRevert();
        registrar.transferOwnership(newOwner);
    }
}
