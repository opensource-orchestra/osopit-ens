# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Durin is an ENS L2 subnames system consisting of:
- L1 Resolver: Forwards ENS queries to L2 via CCIP Read
- L2 Registry Factory: Creates new registries on supported L2 chains
- L2 Registry: Stores subnames as ERC721 NFTs with address/text records
- L2 Registrar: Customizable template for minting subnames
- Gateway Server: Hono-based CCIP Read gateway server

## Architecture

The system operates across L1 and L2:
1. L1Resolver on mainnet/sepolia receives ENS queries and triggers CCIP Read (OffchainLookup error)
2. Gateway server queries the L2Registry on the target chain
3. L2Registry stores subnames as ERC721 tokens and resolver data
4. Only approved Registrars can call `createSubnode()` on L2Registry
5. L2Registrar template is meant to be customized with pricing, allowlists, token gating

## Common Commands

### Smart Contracts (Foundry)

Build contracts:
```bash
forge build
```

Run tests:
```bash
forge test
forge test -vvv  # verbose output
forge test --match-test testFunctionName  # run specific test
```

Deploy L2 contracts to multiple chains:
```bash
./bash/DeployL2Contracts.sh  # requires .env with CREATE2_DEPLOYER_ADDRESS, L2_REGISTRY_IMPLEMENTATION_ADDRESS, L2_REGISTRY_FACTORY_SALT
```

Deploy L2Registrar:
```bash
./bash/DeployL2Registrar.sh  # requires .env with L2_RPC_URL, L2_REGISTRY_ADDRESS, ETHERSCAN_API_KEY
```

Deploy L1Resolver:
```bash
./bash/DeployL1Resolver.sh
```

Verify contracts:
```bash
./bash/VerifyL2Contracts.sh  # verify L2 contracts on single chain
./bash/VerifyAllL2Contracts.sh  # verify across multiple chains
./bash/VerifyL1Resolver.sh  # verify L1 resolver
```

### Gateway Server (Bun)

Navigate to gateway directory for all gateway commands:
```bash
cd gateway
```

Run locally:
```bash
bun run dev  # with watch mode
bun run start  # without watch
```

Build:
```bash
bun run build
```

Deploy to Cloudflare Workers:
```bash
wrangler deploy
```

## Key Contracts

### L2Registry.sol
- Combined Registry, BaseRegistrar, and PublicResolver functionality
- Inherits ERC721 for subname ownership
- Implements L2Resolver for address/text/contenthash records
- Only approved registrars can create subnodes via `createSubnode()`
- Owner can add/remove registrars via `addRegistrar()`/`removeRegistrar()`

### L1Resolver.sol
- Implements IExtendedResolver
- Throws OffchainLookup error for CCIP Read
- Maps ENS nodes to L2 registry address + chain ID via `setL2Registry()`
- Verifies gateway responses using signature verification

### L2Registrar.sol (Example)
- Template meant to be customized
- Must call `registry.createSubnode()` to mint subnames
- Customize with pricing, allowlists, token gating logic

### L2RegistryFactory.sol
- Deploys L2Registry instances via minimal proxy pattern
- Deployed at `0xDddddDdDDD8Aa1f237b4fa0669cb46892346d22d` on supported chains

## Configuration

### .env Variables
Required for L2Registrar deployment:
- `L2_RPC_URL`: RPC endpoint for target L2 chain
- `L2_REGISTRY_ADDRESS`: Address of deployed L2Registry
- `ETHERSCAN_API_KEY`: For contract verification

Pre-configured constants (for new chain deployments):
- `CREATE2_DEPLOYER_ADDRESS`: 0x13b0D85CcB8bf860b6b79AF3029fCA081AE9beF2
- `L1_RESOLVER_ADDRESS`: 0x8A968aB9eb8C084FBC44c531058Fc9ef945c3D61
- `L1_RESOLVER_URL`: https://gateway.durin.dev/v1/{sender}/{data}

### Supported L2 Chains
All chains have L2RegistryFactory at `0xDddddDdDDD8Aa1f237b4fa0669cb46892346d22d`:
- Arbitrum, Base, Celo, Linea, Optimism, Polygon, Scroll, Worldchain
- Test networks: Arbitrum Sepolia, Base Sepolia, Celo Sepolia, Linea Sepolia, Optimism Sepolia, Polygon Amoy, Scroll Sepolia, Worldchain Sepolia

RPC endpoints are configured in `foundry.toml` and gateway's `query.ts`.

## Gateway Implementation

The gateway server (gateway/src/):
- Built with Hono framework, runs on Cloudflare Workers or Bun
- Main handler at `/v1/:sender/:data` decodes CCIP Read requests
- `query.ts` contains chain configurations and viem clients
- Uses Alchemy providers for RPC calls
- Reads from L2Registry contracts and returns signed responses

Adding a new chain requires:
1. Adding chain to `supportedChains` array in `gateway/src/ccip-read/query.ts`
2. Deploying L2 contracts via `DeployL2Contracts.s.sol`

## Invite-Based Registration System

The L2Registrar has been extended with an invite-based registration system:

### Contract Implementation

**State Variables:**
- `mapping(address => bool) public inviters` - Whitelist of approved inviters
- `mapping(bytes32 => bool) public usedInvites` - Tracks used invite signatures (prevents replay)
- `address public immutable owner` - Contract owner for admin functions

**Admin Functions:**
- `addInviter(address)` - Add address to inviter whitelist (onlyOwner)
- `removeInviter(address)` - Remove address from whitelist (onlyOwner)

**Registration Function:**
```solidity
function registerWithInvite(
    string calldata label,
    address owner,
    uint256 expiration,
    address inviter,
    bytes calldata signature
) external
```

**Signature Format:**
- Message: `keccak256(abi.encodePacked(address(registrar), label, owner, expiration))`
- Wrapped with EIP-191: `toEthSignedMessageHash()`
- Validated using UniversalSignatureValidator at 0x164af34fAF9879394370C7f09064127C043A35E9

### Frontend Implementation

**Invite Generation (/invite page):**
1. Whitelisted wallet connects
2. Inputs subdomain, optional recipient address, expiration
3. Signs message client-side via `signMessage`
4. Generates shareable URL: `/onboarding?invite={base64EncodedData}`

**Onboarding Flow (/onboarding page):**
1. Checks URL params for `?invite=...` code
2. Decodes and validates expiration
3. Pre-fills subdomain (locked for editing)
4. Shows invite badge with inviter address
5. Passes invite data to registration hook

**useCreateProfile Hook:**
1. Uploads avatar to IPFS (placeholder - needs Pinata/Thirdweb/NFT.Storage)
2. Calls `L2Registrar.registerWithInvite()` with signature
3. Sets ENS text records via L2Registry multicall:
   - `description` (bio)
   - `avatar` (IPFS URL)
   - `app.osopit.socials` (JSON)
   - `app.osopit.streaming` (false)

### Deployment Steps

1. Deploy updated L2Registrar with invite logic
2. Call `L2Registry.addRegistrar(newRegistrarAddress)`
3. Call `L2Registrar.addInviter(address)` for each approved inviter
4. Update L2_REGISTRAR_ADDRESS in web app (`/apps/web/src/hooks/useCreateProfile.ts` and `/apps/web/src/app/invite/page.tsx`)

### Security Fixes Applied

**Critical vulnerabilities fixed:**

1. **register() bypass vulnerability (FIXED)**
   - Previously: Anyone could call `register()` and bypass entire invite system
   - Now: `register()` restricted to `onlyOwner` for admin/emergency use only
   - Regular users MUST use `registerWithInvite()` with valid signature

2. **Recipient validation (FIXED)**
   - Added check: `if (recipient != address(0) && msg.sender != recipient) revert Unauthorized()`
   - Prevents unauthorized registration even with valid invite signature
   - Ensures only intended recipient can use invite

3. **Checks-effects-interactions pattern (FIXED)**
   - Moved `usedInvites[inviteId] = true` before external calls
   - Prevents potential reentrancy attacks

4. **setAddr call order (FIXED)**
   - Moved `createSubnode()` BEFORE `setAddr()` calls
   - Node must exist before setting addresses

5. **Parameter shadowing (FIXED)**
   - Renamed `address owner` → `address recipient` throughout
   - Eliminates compiler warnings

6. **OpenZeppelin Ownable (IMPLEMENTED)**
   - Replaced manual owner implementation with battle-tested OZ Ownable
   - Gains `transferOwnership()` and `renounceOwnership()` capabilities
   - Industry standard, audited code

### Frontend Improvements Applied

1. **Node hash calculation (IMPLEMENTED)**
   - Fetches `baseNode` from L2Registry via RPC
   - Correctly calculates node: `keccak256(baseNode || labelHash)`
   - Text records now set properly

2. **Transaction receipt waiting (IMPLEMENTED)**
   - Replaced all `setTimeout` with `waitForTransactionReceipt`
   - Checks `receipt.status === 'reverted'`
   - Proper error handling

3. **Error parsing (IMPLEMENTED)**
   - Specific error messages for: `InviteAlreadyUsed`, `SignatureExpired`, `InvalidInviter`, `NotAvailable`, `Unauthorized`
   - User-friendly feedback

4. **Recipient validation in UI (IMPLEMENTED)**
   - Checks if invite is for specific address
   - Validates connected wallet matches
   - Shows warnings appropriately

5. **IPFS upload (IMPLEMENTED)**
   - Backend API route `/api/upload-ipfs` using Pinata
   - Validates file size (max 10MB) and type (images only)
   - Secure JWT handling server-side

6. **Subdomain validation (IMPLEMENTED)**
   - Real-time validation: min 3, max 32 chars, alphanumeric + hyphens
   - Cannot start/end with hyphen
   - Button disabled when invalid

### Helper Scripts

**Generate invite signatures:**
```bash
# Install dependencies
bun install

# Generate invite (defaults: label=alice, recipient=0x0, expiration=7 days)
bun run generate-invite

# Generate invite with custom parameters
bun run generate-invite myname 0xRecipientAddress 14

# Required environment variable
export INVITER_PRIVATE_KEY=0x...
export L2_REGISTRAR_ADDRESS=0x...
```

The script outputs:
- Invite URL with base64-encoded signature
- Cast command for CLI testing
- Full invite details for debugging

### TODOs (Configuration Only)

- Configure PINATA_JWT in `.env` (required for avatar uploads)
- Update L2_REGISTRAR_ADDRESS after deployment
- Deploy to Base Sepolia for testing before mainnet

## Development Notes

- Solidity version: 0.8.24 (Cancun EVM)
- Uses OpenZeppelin, ENS contracts, and solidity-stringutils libraries
- Test framework: Foundry with 256 fuzz runs
- Gateway and frontend use viem for Ethereum interactions
- Scripts use Bun runtime with TypeScript (no build step)
- L2Registry stores names in DNS-encoded format (see ENSDNSUtils.sol)
- Signature verification uses UniversalSigValidator at 0x164af34fAF9879394370C7f09064127C043A35E9
  - Deployed on Base mainnet (verified)
  - EIP-6492 compliant (supports counterfactual contracts)
  - EIP-1271 compliant (supports smart contract wallets)
  - Source: ENS contracts, deterministically deployed via Nick's Method
