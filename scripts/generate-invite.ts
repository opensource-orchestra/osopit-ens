// Helper script to generate invite signatures
// Usage: bun run generate-invite [label] [recipient] [expirationDays]

import { privateKeyToAccount } from 'viem/accounts';
import { keccak256, encodePacked, type Hex, type Address } from 'viem';
import { z } from 'zod';

const envShcema = z.object({
  L2_REGISTRAR_ADDRESS: z.string(),
  INVITER_PRIVATE_KEY: z.string(),
});

const env = envShcema.parse(process.env);

// Types
interface InviteData {
  label: string;
  recipient: Hex;
  expiration: number;
  inviter: Hex;
  signature: Hex;
}

// Configuration
const REGISTRAR_ADDRESS = env.L2_REGISTRAR_ADDRESS;
const INVITER_PRIVATE_KEY = env.INVITER_PRIVATE_KEY;

// Invite parameters
const label = process.argv[2] || 'alice';
const recipient = (process.argv[3] || '0x0000000000000000000000000000000000000000') as Hex;
const expirationDays = parseInt(process.argv[4] || '7');

async function generateInvite(): Promise<InviteData> {
  if (!INVITER_PRIVATE_KEY) {
    console.error('ERROR: INVITER_PRIVATE_KEY environment variable not set');
    process.exit(1);
  }

  // Calculate expiration timestamp
  const expiration = Math.floor(Date.now() / 1000) + (expirationDays * 24 * 60 * 60);

  console.log('=================================================');
  console.log('Generating Invite Signature');
  console.log('=================================================');
  console.log('Registrar:', REGISTRAR_ADDRESS);
  console.log('Label:', label);
  console.log('Recipient:', recipient === '0x0000000000000000000000000000000000000000' ? 'Anyone' : recipient);
  console.log('Expires in:', expirationDays, 'days');
  console.log('Expiration timestamp:', expiration);
  console.log('');

  // Create message hash to sign
  const messageHash = keccak256(
    encodePacked(
      ['address', 'string', 'address', 'uint256'],
      [REGISTRAR_ADDRESS as Address, label, recipient, BigInt(expiration)]
    )
  );

  console.log('Message hash:', messageHash);

  // Sign with inviter wallet
  const account = privateKeyToAccount(INVITER_PRIVATE_KEY as `0x${string}`);
  const signature = await account.signMessage({
    message: { raw: messageHash },
  });

  console.log('Inviter address:', account.address);
  console.log('Signature:', signature);
  console.log('');

  // Generate invite data
  const inviteData: InviteData = {
    label,
    recipient,
    expiration,
    inviter: account.address,
    signature,
  };

  // Encode for URL using Bun's built-in btoa
  const inviteCode = btoa(JSON.stringify(inviteData));
  const inviteUrl = `https://osopit.com/onboarding?invite=${inviteCode}`;

  console.log('=================================================');
  console.log('Invite Generated Successfully!');
  console.log('=================================================');
  console.log('');
  console.log('Invite URL:');
  console.log(inviteUrl);
  console.log('');
  console.log('Cast command to test (replace $RECIPIENT_PRIVATE_KEY):');
  console.log(`cast send ${REGISTRAR_ADDRESS} \\`);
  console.log(`  "registerWithInvite(string,address,uint256,address,bytes)" \\`);
  console.log(`  "${label}" \\`);
  console.log(`  "${recipient}" \\`);
  console.log(`  ${expiration} \\`);
  console.log(`  "${account.address}" \\`);
  console.log(`  "${signature}" \\`);
  console.log(`  --rpc-url $L2_RPC_URL \\`);
  console.log(`  --private-key $RECIPIENT_PRIVATE_KEY`);
  console.log('');

  return inviteData;
}

// Run if called directly
if (import.meta.main) {
  generateInvite().catch((error) => {
    console.error('Error generating invite:', error);
    process.exit(1);
  });
}

export { generateInvite };
