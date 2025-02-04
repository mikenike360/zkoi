program zkoi_test2.aleo {

    // Constant to define the hardcoded contract owner address.
    // This ensures that specific administrative tasks are restricted to this address.
    const contract_owner: address = aleo1xh0ncflwkfzga983lwujsha729c8nwu7phfn8aw7h3gahhj0ms8qytrxec;

    // Constant to define a default null address
    const NULL_ADDRESS: address = aleo1qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq3ljyzc;


    // Struct to define the BaseURI for NFTs.
    // Typically used to store components of a URI in a structured way.
    struct BaseURI {
        data0: u128,
        data1: u128,
        data2: u128,
        data3: u128,
    }

    // Struct to represent a unique Token ID.
    // Token IDs are composed of two 128-bit integers.
    struct TokenId {
        id0: u128,
        id1: u128,
    }

    // Struct to represent an approval relationship.
    // This tracks an address granting another address permission to perform specific actions.
    struct approval {
        approver: address,
        spender: address,
    }

    // Struct to represent the content of an NFT.
    // Includes metadata and the edition information of the NFT.
    struct nft_content {
        data: TokenId,
        edition: scalar
    }

    // Record to store details of an NFT minting process.
    // Tracks the address of the minter, the amount minted, and the owner of the record.
    record NFT_mint {
        private minter_address: address,
        private amount: u8,
        private owner: address,
    }

    // Record to track NFT claims.
    // Stores the claiming address, the cryptographic claim, and the owner of the record.
    record NFT_claim {
        private claim_owner: address,
        private claim: field,
        private owner: address,
    }   

    // Record to represent a publicly visible NFT.
    // Includes the owner of the NFT, its TokenId, edition, and the record owner.
    record PublicNFT {
        public nft_owner: address,   // Public because it needs to be visible
        private data: TokenId,       // TokenId can remain private
        private edition: scalar,     // Edition should also be private
        private owner: address,      // Owner must be private to enforce access control
    }   

    // Record to represent a private NFT.
    // Tracks the owner, the NFT's data, and its edition.
    record NFT {
        private owner: address,
        private data: TokenId,
        private edition: scalar,
    }

    // Record to represent an NFT viewable by the public.
    // Includes private owner and edition fields, along with a public visibility flag.
    record NFTView {
        private owner: address,
        private data: TokenId,
        private edition: scalar,
        public is_view: bool         // Public because it explicitly indicates visibility
    }

    // Mapping to store toggle settings for the contract.
    // The key (`u8`) represents a setting identifier, and the value (`u32`) stores the setting state.
    mapping toggle_settings: u8 => u32;

    // Mapping to store general settings for the contract.
    // The key (`u8`) represents a setting identifier, and the value (`u128`) stores the setting value.
    mapping general_settings: u8 => u128;

    // Mapping to store NFTs available for minting.
    // The key (`u128`) represents an NFT identifier, and the value (`field`) represents the NFT's metadata or commitment.
    mapping nfts_to_mint: u128 => field;

    // Mapping to link claims to NFTs.
    // The key (`field`) represents a claim, and the value (`field`) links to the associated NFT's data or commitment.
    mapping claims_to_nfts: field => field;

    // Mapping to track NFT commitments.
    // The key (`field`) represents an NFT commitment, and the value (`bool`) indicates whether the commitment exists.
    mapping nft_commits: field => bool;

    // Mapping to track NFT ownership.
    // The key (`field`) represents an NFT commitment, and the value (`address`) stores the owner's address.
    mapping nft_owners: field => address;

    // Mapping to store global approval states for NFTs.
    // The key (`field`) represents an NFT identifier, and the value (`bool`) indicates whether approval is granted for all.
    mapping for_all_approvals: field => bool;

    // Mapping to store individual NFT approvals.
    // The key (`field`) represents an NFT identifier, and the value (`field`) stores the approval-related data.
    mapping nft_approvals: field => field;

    // Mapping to store additional NFT content.
    // The key (`field`) represents an NFT identifier, and the value (`nft_content`) contains the associated metadata and edition information.
    mapping nft_contents: field => nft_content;

    // Inline function to generate a cryptographic commitment for an NFT.
    // Combines the NFT's metadata (`nft_data`) and its edition (`nft_edition`) to produce a unique commitment.
    //
    // Inputs:
    // - `nft_data`: A `TokenId` struct containing the unique identifiers for the NFT.
    // - `nft_edition`: A scalar value representing the edition number of the NFT.
    //
    // Output:
    // - Returns a `field` representing the cryptographic commitment for the NFT.
    inline commit_nft(
        nft_data: TokenId,
        nft_edition: scalar
    ) -> field {
        let data_hash: field = BHP256::hash_to_field(nft_data); // Hash the NFT data for integrity and uniqueness.
        let commitment: field = BHP256::commit_to_field(data_hash, nft_edition); // Create a commitment using the hash and edition.
        return commitment;
    }

    // Transition to transfer an NFT privately.
    // Assumes frontend validation ensures the NFT is owned by the caller and the recipient (`to`) is valid.
    // Updates the owner field of the NFT while retaining its original data and edition.
    //
    // Inputs:
    // - `nft`: A private `NFT` record representing the NFT to be transferred.
    // - `to`: A private `address` specifying the recipient of the NFT.
    //
    // Output:
    // - Returns a new `NFT` record with the updated owner field.
    transition transfer_private(
        private nft: NFT,
        private to: address,
    ) -> NFT {
        assert_eq(nft.owner, self.caller); // Ensure the caller is the current owner of the NFT.
        return NFT {
            owner: to,          // Assign the new owner to the recipient address.
            data: nft.data,     // Retain the original NFT's data.
            edition: nft.edition // Retain the original NFT's edition.
        };
    }

    // Async transition to transfer a private NFT to a public NFT.
    // This transition updates the NFT's visibility and transfers ownership to the recipient.
    //
    // Inputs:
    // - `nft`: A private `NFT` record representing the NFT to be transferred.
    // - `to`: A public `address` specifying the recipient of the NFT.
    //
    // Output:
    // - Returns an `NFTView` (public representation of the NFT) and a `Future` to finalize the transfer.
    async transition transfer_priv_to_pub(
        private nft: NFT,
        public to: address,
    ) -> (NFTView, Future) {
        assert_eq(nft.owner, self.caller); // Ensure the caller is the current owner of the NFT.
        let nft_commit: field = commit_nft(nft.data, nft.edition);

        let nft_view: NFTView = NFTView {
            owner: to,
            data: nft.data,
            edition: nft.edition,
            is_view: true
        };
        let transfer_future: Future = finalize_transfer_priv_to_pub(
            to, nft_commit
        );
        return (nft_view, transfer_future);
    }

    // Finalizes the transfer and updates ownership.
    async function finalize_transfer_priv_to_pub(
        to: address,
        nft_commit: field,
    ) {
        nft_owners.set(nft_commit, to); // Update ownership mapping.
    }

    // Async transition to transfer a public NFT to another address.
    // Ensures the NFT is associated with a public recipient and updates its ownership.
    //
    // Inputs:
    // - `nft_data`: A private `TokenId` struct representing the NFT's unique identifier.
    // - `nft_edition`: A private scalar representing the NFT's edition number.
    // - `to`: A public address specifying the recipient of the NFT.
    //
    // Output:
    // - Returns an `NFTView` representing the public NFT and a `Future` to finalize the transfer.
    async transition transfer_public(
        private nft_data: TokenId,
        private nft_edition: scalar,
        public to: address,
    ) -> (NFTView, Future) {
        let nft_commit: field = commit_nft(nft_data, nft_edition);
        let caller: address = self.caller;

        let nft_view: NFTView = NFTView {
            owner: to,
            data: nft_data,
            edition: nft_edition,
            is_view: true
        };

        let transfer_future: Future = finalize_transfer_public(
            to, nft_commit, caller
        );

        return (nft_view, transfer_future);
    }

    // Async function to finalize the transfer of a public NFT.
    // Updates the ownership mapping and removes any existing approvals.
    //
    // Inputs:
    // - `to`: The recipient's address.
    // - `nft_commit`: The cryptographic commitment of the NFT being transferred.
    // - `caller`: The address of the current owner initiating the transfer.
    async function finalize_transfer_public(
        to: address,
        nft_commit: field,
        caller: address,
    ) {
        let owner: address = nft_owners.get(nft_commit);
        assert_eq(caller, owner);
        nft_approvals.remove(nft_commit);
        nft_owners.set(nft_commit, to);
    }

    // Async transition to transfer a public NFT using the signer's address for ownership validation.
    // Ensures the NFT is associated with a public recipient and updates its ownership.
    //
    // Inputs:
    // - `nft_data`: A private `TokenId` struct representing the NFT's unique identifier.
    // - `nft_edition`: A private scalar representing the NFT's edition number.
    // - `to`: A public address specifying the recipient of the NFT.
    //
    // Output:
    // - Returns an `NFTView` representing the public NFT and a `Future` to finalize the transfer.
    async transition transfer_pub_as_signer(
        private nft_data: TokenId,
        private nft_edition: scalar,
        public to: address,
    ) -> (NFTView, Future) {
        let nft_commit: field = commit_nft(nft_data, nft_edition);
        let signer: address = self.signer;

        let nft_view: NFTView = NFTView {
            owner: to,
            data: nft_data,
            edition: nft_edition,
            is_view: true
        };

        let transfer_future: Future = finalize_transfer_pub_as_signer(
            to, nft_commit, signer
        );

        return (nft_view, transfer_future);
    }

    // Async function to finalize the transfer of a public NFT using the signer for ownership validation.
    // Updates the ownership mapping and removes any existing approvals.
    //
    // Inputs:
    // - `to`: The recipient's address.
    // - `nft_commit`: The cryptographic commitment of the NFT being transferred.
    // - `signer`: The address of the current owner initiating the transfer.
    async function finalize_transfer_pub_as_signer(
        to: address,
        nft_commit: field,
        signer: address,
    ) {
        let owner: address = nft_owners.get(nft_commit);
        assert_eq(signer, owner);
        nft_approvals.remove(nft_commit);
        nft_owners.set(nft_commit, to);
    }

    // Async transition to transfer a public NFT to a private NFT.
    // Ensures the NFT is securely transferred to a private recipient and updates its representation.
    //
    // Inputs:
    // - `nft_data`: A private `TokenId` struct representing the NFT's unique identifier.
    // - `nft_edition`: A private scalar representing the NFT's edition number.
    // - `to`: A private address specifying the recipient of the NFT.
    //
    // Output:
    // - Returns an `NFT` representing the private NFT and a `Future` to finalize the transfer.
    async transition transfer_pub_to_priv(
        private nft_data: TokenId,
        private nft_edition: scalar,
        private to: address,
    ) -> (NFT, Future) {
        let nft_commit: field = commit_nft(nft_data, nft_edition); // Generate the cryptographic commitment for the NFT.
        let caller: address = self.caller; // Capture the caller's address.

        let finalize_future: Future = finalize_transfer_pub_to_priv(
            caller, nft_commit
        );

        let received_nft: NFT = NFT {
            owner: to,
            data: nft_data,
            edition: nft_edition,
        };

        return (received_nft, finalize_future);
    }

    // Async function to finalize the transfer of a public NFT to a private NFT.
    // Removes the public NFT's approvals and ownership mapping, completing the transition.
    //
    // Inputs:
    // - `caller`: The address of the current owner initiating the transfer.
    // - `nft_commit`: The cryptographic commitment of the NFT being transferred.
    async function finalize_transfer_pub_to_priv(
        caller: address,
        nft_commit: field,
    ) {
        let owner: address = nft_owners.get(nft_commit); // Retrieve the current owner.
        assert_eq(caller, owner); // Validate the caller is the current owner.
        nft_approvals.remove(nft_commit); // Remove any existing approvals for the NFT.
        nft_owners.remove(nft_commit); // Remove the NFT from the public ownership mapping.
    }

    // Async transition to set or revoke approval for a specific spender across all NFTs.
    // Generates a cryptographic hash representing the approval relationship and schedules a `Future` to update the approval mapping.
    //
    // Inputs:
    // - `spender`: A private address representing the entity being granted or revoked approval.
    // - `new_value`: A public boolean indicating whether to grant (`true`) or revoke (`false`) approval.
    //
    // Output:
    // - Returns a `Future` to finalize the update in the `for_all_approvals` mapping.
    async transition set_for_all_approval(
        private spender: address,
        public new_value: bool,
    ) -> Future {
        let apvl: approval = approval {
            approver: self.caller, // Caller initiating the approval action.
            spender: spender,     // Address of the spender being approved or revoked.
        };
        let apvl_hash: field = BHP256::hash_to_field(apvl); // Generate a cryptographic hash of the approval relationship.

        return finalize_set_for_all_approval(
            apvl_hash, new_value // Schedule the approval update with the hash and new value.
        );
    }

    // Async function to finalize the update to the approval mapping.
    // Includes checks for existing approvals to prevent accidental overwrites.
    async function finalize_set_for_all_approval(
        apvl_hash: field,
        new_value: bool,
    ) {
        let current_value: bool = for_all_approvals.get_or_use(apvl_hash, false);

        // Only update if the new value differs from the current value
        if current_value != new_value {
            for_all_approvals.set(apvl_hash, new_value);
        }
    }

    // Async transition to approve a specific spender for a public NFT.
    // Grants the spender permission to interact with a specific NFT.
    //
    // Inputs:
    // - `spender`: A private address representing the spender being approved.
    // - `nft_data`: A private `TokenId` struct representing the unique identifier of the NFT.
    // - `nft_edition`: A private scalar representing the edition of the NFT.
    //
    // Output:
    // - Returns a `Future` to finalize the approval process.
    async transition approve_public(
        private spender: address,
        private nft_data: TokenId,
        private nft_edition: scalar,
    ) -> Future {
        assert(spender != NULL_ADDRESS); // Ensure the spender address is valid.
        assert_eq(nft_data.id0 > 0u128, true); // Validate TokenId initialization.
        assert_eq(nft_edition > 0scalar, true); // Ensure the edition is greater than zero.

        let nft_commit: field = commit_nft(nft_data, nft_edition); // Generate the cryptographic commitment for the NFT.

        let apvl: approval = approval {
            approver: self.caller, // Caller initiating the approval action.
            spender: spender,     // Spender being approved.
        };
        let apvl_hash: field = BHP256::hash_to_field(apvl); // Generate a cryptographic hash of the approval relationship.

        let existing_approval: field = nft_approvals.get_or_use(nft_commit, 0field);
        assert_eq(existing_approval, 0field); // Ensure no existing approval exists for this NFT.

        return finalize_approve_public(
            self.caller, apvl_hash, nft_commit // Schedule the finalization of the approval with the necessary details.
        );
    }

    // Async function to finalize the approval of a public NFT.
    // Updates the approval mapping.
    //
    // Inputs:
    // - `caller`: The address of the current owner initiating the approval.
    // - `apvl_hash`: A cryptographic hash representing the approval relationship.
    // - `nft_commit`: The cryptographic commitment of the NFT being approved.
    async function finalize_approve_public(
        caller: address,
        apvl_hash: field,
        nft_commit: field,
    ) {
        nft_approvals.set(nft_commit, apvl_hash); // Update the mapping to reflect the new approval.
    }


    async transition transfer_from_public(
        public from: address,
        public to: address,
        private nft_data: TokenId,
        private nft_edition: scalar,
    ) -> (NFTView, Future) {
        let nft_commit: field = commit_nft(nft_data, nft_edition);

        let nft_view: NFTView = NFTView {
            owner: to,
            data: nft_data,
            edition: nft_edition,
            is_view: true
        };

        let apvl: approval = approval {
            approver: from,
            spender: self.caller,
        };
        let apvl_hash: field = BHP256::hash_to_field(apvl);

        let transfer_future: Future = finalize_transfer_from_public(
            apvl_hash, from, to, nft_commit
        );

        return (nft_view, transfer_future);
    }

    async function finalize_transfer_from_public(
        apvl_hash: field,
        from: address,
        to: address,
        nft_commit: field,
    ) {
        assert(
            nft_approvals.contains(nft_commit)
            || for_all_approvals.get_or_use(apvl_hash, false)
        );

        let owner: address = nft_owners.get(nft_commit);
        assert_eq(from, owner);

        nft_approvals.remove(nft_commit);
        nft_owners.set(nft_commit, to);
    }

    async transition update_edition_private(
        private nft: NFT,
        private new_edition: scalar,
    ) -> (NFT, Future) {
        let out_nft: NFT = NFT {
            owner: nft.owner,
            data: nft.data,
            edition: new_edition,
        };
        let nft_commit: field = commit_nft(nft.data, new_edition);

        let update_future: Future = finalize_update_edition_private(
            nft_commit
        );

        return (out_nft, update_future);
    }

    async function finalize_update_edition_private(
        nft_commit: field,
    ) {
        assert(nft_commits.contains(nft_commit).not());
        nft_commits.set(nft_commit, true);
    }

    async transition publish_nft_content(
        public nft_data: TokenId,
        public nft_edition: scalar,
    ) -> Future {
        let nft_commit: field = commit_nft(nft_data, nft_edition);

        let publish_future: Future = finalize_publish_nft_content(
            nft_commit,
            nft_data,
            nft_edition
        );

        return publish_future;
    }

    async function finalize_publish_nft_content(
        nft_commit: field,
        nft_data: TokenId,
        nft_edition: scalar,
    ) {
        let public_data: nft_content = nft_content {
            data: nft_data,
            edition: nft_edition
        };
        nft_contents.set(nft_commit, public_data);
    }

    //Custom Functions Here


    //Custom Mint Function
    async transition mint(
        private nft_data: TokenId,
        private nft_edition: scalar,
        private to: address,
    ) -> (NFT, Future) {
        // Create a unique commitment for the new NFT.
        let nft_commit: field = commit_nft(nft_data, nft_edition);

        // Call the async function to validate and store the NFT.
        let mint_future: Future = finalize_mint(nft_commit, to);

        // Return the new NFT and the future.
        let nft: NFT = NFT {
            owner: to,
            data: nft_data,
            edition: nft_edition,
        };

        return (nft, mint_future);
    }

    async function finalize_mint(
        nft_commit: field,
        to: address,
    ) {
        // Ensure the NFT is unique.
        assert(nft_commits.contains(nft_commit).not());

        // Store the NFT commitment and ownership.
        nft_commits.set(nft_commit, true);
        nft_owners.set(nft_commit, to);
    }

    //Custom init 
    async transition initialize_collection(
        public total: u128,
        public symbol: u128,
        public base_uri: BaseURI,
    ) -> Future {
        // Ensure only the specified caller can initialize.
        assert_eq(
            self.caller,
            contract_owner
        );

        // Call the async function to finalize the initialization.
        let init_future: Future = finalize_initialize_collection(
            total, symbol, base_uri
        );

        return init_future;
    }

    async function finalize_initialize_collection(
        total: u128,
        symbol: u128,
        base_uri: BaseURI,
    ) {
        // Ensure initialize cannot be called twice!
        let toggle_settings_status: u32 = toggle_settings.get_or_use(0u8, 0u32);
        let is_initialized: u32 = toggle_settings_status & 1u32;
        assert_eq(is_initialized, 0u32);

        // Set general settings.
        general_settings.set(0u8, 0u128); // Number of mintable NFTs (all editions)
        general_settings.set(1u8, total); // Total NFTs (first-editions)
        general_settings.set(2u8, symbol); // Symbol for the NFT
        general_settings.set(3u8, base_uri.data0); // Base URI (part 0)
        general_settings.set(4u8, base_uri.data1); // Base URI (part 1)
        general_settings.set(5u8, base_uri.data2); // Base URI (part 2)
        general_settings.set(6u8, base_uri.data3); // Base URI (part 3)

        // Initialize toggle settings.
        // Default flags: not frozen, whitelist required, not minting, initialized.
        // Flags value = 0b0000...0101 = 5u32.
        toggle_settings.set(0u8, 5u32);
        toggle_settings.set(1u8, 0u32); // Block height when minting is allowed.
    }

    //Custom add NFT function
    async transition add_nft(
        public tokenId: TokenId,
        public edition: scalar,
    ) -> Future {
        // Ensure only the specified caller can add an NFT.
        assert_eq(
            self.caller,
            contract_owner
        );

        // Compute the token hashes.
        let tokenHash: field = BHP256::hash_to_field(tokenId);
        let tokenEditionHash: field = BHP256::commit_to_field(tokenHash, edition);

        // Call the async function to finalize adding the NFT.
        let add_nft_future: Future = finalize_add_nft(tokenEditionHash);

        return add_nft_future;
    }

    async function finalize_add_nft(
        tokenEditionHash: field,
    ) {
        // Ensure the collection is initialized and not frozen.
        let toggle_settings_status: u32 = toggle_settings.get(0u8);
        // Initialized & frozen flags = 0b0000...1001 = 9u32.
        // Required settings = 0b0000...0001 = 1u32.
        let is_initialized_and_not_frozen: u32 = toggle_settings_status & 9u32;
        assert_eq(is_initialized_and_not_frozen, 1u32);

        // Reduce the amount of total NFTs that can be initialized.
        let remaining: u128 = general_settings.get(1u8);
        general_settings.set(1u8, remaining - 1u128);

        // Add this NFT to the mintable NFT collection.
        let mintable_num: u128 = general_settings.get(0u8);
        nfts_to_mint.set(mintable_num, tokenEditionHash);
        general_settings.set(0u8, mintable_num + 1u128);
    }

    //custom add minter function
    async transition add_minter(
        private minter: address,
        public amount: u8,
    ) -> (NFT_mint, Future) {
        // Ensure only the specified caller can add a minter.
        assert_eq(
            self.caller,
            contract_owner
        );

        // Create the NFT_mint object.
        let nft_mint: NFT_mint = NFT_mint {
            owner: self.caller,
            minter_address: minter,
            amount,
        };

        // Call the async function to finalize adding the minter.
        let add_minter_future: Future = finalize_add_minter();

        return (nft_mint, add_minter_future);
    }

    async function finalize_add_minter() {
        // Ensure the collection is initialized and not frozen.
        let toggle_settings_status: u32 = toggle_settings.get(0u8);
        // Initialized & frozen flags = 0b0000...1001 = 9u32.
        // Required settings = 0b0000...0001 = 1u32.
        let is_initialized_and_not_frozen: u32 = toggle_settings_status & 9u32;
        assert_eq(is_initialized_and_not_frozen, 1u32);
    }

    //custom toggle settings function
    async transition update_toggle_settings(
        public toggle_settings_bitstring: u32,
    ) -> Future {
        // Ensure only the specified caller can update the settings.
        assert_eq(
            self.caller,
            contract_owner
        );

        // Call the async function to finalize updating the toggle settings.
        let update_future: Future = finalize_update_toggle_settings(toggle_settings_bitstring);

        return update_future;
    }

    async function finalize_update_toggle_settings(
        toggle_settings_bitstring: u32,
    ) {
        // Ensure the collection is initialized and not frozen.
        let toggle_settings_status: u32 = toggle_settings.get(0u8);
        // Initialized & frozen flags = 0b0000...1001 = 9u32.
        // Required settings = 0b0000...0001 = 1u32.
        let is_initialized_and_not_frozen: u32 = toggle_settings_status & 9u32;
        assert_eq(is_initialized_and_not_frozen, 1u32);

        // Ensure updated settings do not uninitialize the collection.
        let still_initialized: u32 = toggle_settings_bitstring & 1u32;
        assert_eq(still_initialized, 1u32);

        // Update the toggle settings.
        toggle_settings.set(0u8, toggle_settings_bitstring);
    }

    //custom set mint block function
    async transition set_mint_block(
        public mint_block: u32,
    ) -> Future {
        // Ensure only the specified caller can set the mint block.
        assert_eq(
            self.caller,
            contract_owner
        );

        // Call the async function to finalize setting the mint block.
        let set_block_future: Future = finalize_set_mint_block(mint_block);

        return set_block_future;
    }

    async function finalize_set_mint_block(
        mint_block: u32,
    ) {
        // Ensure the collection is initialized and not frozen.
        let toggle_settings_status: u32 = toggle_settings.get(0u8);
        // Initialized & frozen flags = 0b0000...1001 = 9u32.
        // Required settings = 0b0000...0001 = 1u32.
        let is_initialized_and_not_frozen: u32 = toggle_settings_status & 9u32;
        assert_eq(is_initialized_and_not_frozen, 1u32);

        // Update the mint block in toggle settings.
        toggle_settings.set(1u8, mint_block);
    }

    //custom update collection symbol function
    async transition update_symbol(
        public symbol: u128,
    ) -> Future {
        // Ensure only the specified caller can update the symbol.
        assert_eq(
            self.caller,
            contract_owner
        );

        // Call the async function to finalize updating the symbol.
        let update_symbol_future: Future = finalize_update_symbol(symbol);

        return update_symbol_future;
    }

    async function finalize_update_symbol(
        symbol: u128,
    ) {
        // Ensure the collection is initialized and not frozen.
        let toggle_settings_status: u32 = toggle_settings.get(0u8);
        // Initialized & frozen flags = 0b0000...1001 = 9u32.
        // Required settings = 0b0000...0001 = 1u32.
        let is_initialized_and_not_frozen: u32 = toggle_settings_status & 9u32;
        assert_eq(is_initialized_and_not_frozen, 1u32);

        // Update the symbol in general settings.
        general_settings.set(2u8, symbol);
    }

    //custom update base uri function
    async transition update_base_uri(
        public base_uri: BaseURI,
    ) -> Future {
        // Ensure only the specified caller can update the base URI.
        assert_eq(
            self.caller,
            contract_owner
        );

        // Call the async function to finalize updating the base URI.
        let update_base_uri_future: Future = finalize_update_base_uri(base_uri);

        return update_base_uri_future;
    }

    async function finalize_update_base_uri(
        base_uri: BaseURI,
    ) {
        // Ensure the collection is initialized and not frozen.
        let toggle_settings_status: u32 = toggle_settings.get(0u8);
        // Initialized & frozen flags = 0b0000...1001 = 9u32.
        // Required settings = 0b0000...0001 = 1u32.
        let is_initialized_and_not_frozen: u32 = toggle_settings_status & 9u32;
        assert_eq(is_initialized_and_not_frozen, 1u32);

        // Update the base URI in general settings.
        general_settings.set(3u8, base_uri.data0); // Base URI for NFT (part 0)
        general_settings.set(4u8, base_uri.data1); // Base URI for NFT (part 1)
        general_settings.set(5u8, base_uri.data2); // Base URI for NFT (part 2)
        general_settings.set(6u8, base_uri.data3); // Base URI for NFT (part 3)
    }

    //custom open mint function
    async transition open_mint(
        private hiding_nonce: scalar,
    ) -> (NFT_claim, Future) {
        // CAUTION: If the minter selects the same hiding nonce,
        // that minter will not be able to mint all of their NFTs without claiming some first.
        // Additionally, some privacy will be lost as the claim is a deterministic hash and is held in public state.
        let address_hash: field = BHP256::hash_to_field(self.caller);
        let claim: field = BHP256::commit_to_field(address_hash, hiding_nonce);

        // Create the NFT_claim object.
        let nft_claim: NFT_claim = NFT_claim {
            owner: self.caller,
            claim_owner: self.caller,
            claim,
        };

        // Call the async function to finalize the mint operation.
        let mint_future: Future = finalize_open_mint(claim);

        return (nft_claim, mint_future);
    }

    async function finalize_open_mint(
        claim: field,
    ) {
        // Ensure mint block height is less than the current block height.
        let mint_block: u32 = toggle_settings.get(1u8);
        let passed_height_check: bool = mint_block <= block.height;
        assert_eq(passed_height_check, true);

        // Ensure the collection is not frozen, whitelist is not required, minting is allowed, and is initialized.
        let toggle_settings_status: u32 = toggle_settings.get(0u8);
        // Frozen & whitelist & minting & initialized flags = 0b0000...1111 = 15u32.
        // Required settings = 0b0000...0011 = 3u32.
        let collection_settings_met: u32 = toggle_settings_status & 15u32;
        assert_eq(collection_settings_met, 3u32);

        // Ensure this claim has not already been made.
        let existing_claim: field = claims_to_nfts.get_or_use(claim, 0field);
        assert_eq(existing_claim, 0field);

        // Randomly select an NFT to mint.
        let randomNum: u128 = ChaCha::rand_u128();
        let old_mintable_sum: u128 = general_settings.get_or_use(0u8, 0u128);
        let randomIndex: u128 = randomNum % old_mintable_sum;
        let tokenEditionHash: field = nfts_to_mint.get(randomIndex);
        claims_to_nfts.set(claim, tokenEditionHash);

        // Decrease the number of mintable NFTs.
        let new_mintable_num: u128 = old_mintable_sum - 1u128;
        general_settings.set(0u8, new_mintable_num);

        // Replace the minted NFT from the mintable NFTs with the last mintable NFT.
        // This ensures that the minted NFT is not minted again.
        nfts_to_mint.set(randomIndex, nfts_to_mint.get(new_mintable_num));
    }

    ////custo claim
    // Transition to Claim NFT
    async transition claim_nft(
        nft_claim: NFT_claim,        // Must include a claim field (type field).
        private tokenId: TokenId,    // Must be hashable or convertible to field.
        private edition: scalar,     // Scalar value for edition.
    ) -> (PublicNFT, Future<Fn(field, field)>) {
        // Hash the TokenId.
        let tokenHash: field = BHP256::hash_to_field(tokenId); // Ensure `tokenId` is compatible.

        // Create a commitment for the NFT edition.
        let tokenEditionHash: field = BHP256::commit_to_field(tokenHash, edition);

        // Create the PublicNFT object to represent the claimed NFT.
        let public_nft: PublicNFT = PublicNFT {
            owner: self.caller,
            nft_owner: nft_claim.claim_owner,
            data: tokenId,
            edition,
        };

        let claim_future: Future<Fn(field, field)> = finalize_claim_nft(nft_claim.claim, tokenEditionHash);

        // Return the claimed NFT and the Future for finalization.
        return (public_nft, claim_future);
    }

    // Function to Finalize the Claim
    async function finalize_claim_nft(
        claim: field,                // The claim hash.
        tokenEditionHash: field,     // The hash of the token and edition.
    ) {
        // Retrieve the claimed NFT from the mapping.
        let claimedNFT: field = claims_to_nfts.get(claim);

        // Assert that the claim matches the NFT hash.
        assert_eq(claimedNFT, tokenEditionHash);

        // Mark the claim as used by resetting it in the mapping.
        claims_to_nfts.set(claim, 0field);
    }
}
