use starknet::ContractAddress;

#[starknet::interface]
pub trait IPiggyBank<TContractState> {
    fn get_owner(self: @TContractState) -> ContractAddress;
    fn get_lock_timestamp(self: @TContractState) -> u64;
    fn get_current_balance(self: @TContractState) -> u256;
    fn get_block_timestamp(self: @TContractState) -> u64;
    fn deposit(ref self: TContractState, amount: u256, lock_timestamp: u64);
    fn withdraw(ref self: TContractState);
}

#[starknet::contract]
pub mod PiggyBank {
    // *************************************************************************
    //                            IMPORTS
    // *************************************************************************
    use openzeppelin::token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};
    use starknet::{
        ContractAddress, get_caller_address, get_contract_address, get_block_timestamp,
    };

    // *************************************************************************
    //                            EVENTS
    // *************************************************************************
    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        Deposit: DepositEvent,
        Withdraw: WithdrawEvent,
        OwnershipTransferred: OwnershipTransferredEvent,
        EmergencyWithdraw: EmergencyWithdrawEvent,
    }

    #[derive(Drop, starknet::Event)]
    struct DepositEvent {
        owner: ContractAddress,
        amount: u256,
        lock_timestamp: u64,
    }

    #[derive(Drop, starknet::Event)]
    struct WithdrawEvent {
        owner: ContractAddress,
        amount: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct OwnershipTransferredEvent {
        previous_owner: ContractAddress,
        new_owner: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    struct EmergencyWithdrawEvent {
        owner: ContractAddress,
        amount: u256,
    }

    // *************************************************************************
    //                            STORAGE
    // *************************************************************************
    #[storage]
    struct Storage {
        owner: ContractAddress,
        lock_timestamp: u64,
        is_locked: bool,
    }

    // *************************************************************************
    //                            CONSTRUCTOR
    // *************************************************************************
    #[constructor]
    fn constructor(
        ref self: ContractState
    ) {
        self.owner.write(get_caller_address());
        self.lock_timestamp.write(0);
        self.is_locked.write(false);
    }

    // *************************************************************************
    //                            EXTERNAL FUNCTIONS
    // *************************************************************************
    #[abi(embed_v0)]
    impl PiggyBankImpl of super::IPiggyBank<ContractState> {
        fn get_owner(self: @ContractState) -> ContractAddress {
            self.owner.read()
        }

        fn get_lock_timestamp(self: @ContractState) -> u64 {
            self.lock_timestamp.read()
        }

        fn get_current_balance(self: @ContractState) -> u256 {
            self.token_dispatcher().balance_of(get_contract_address())
        }

        fn get_block_timestamp(self: @ContractState) -> u64 {
            get_block_timestamp()
        }

        fn deposit(ref self: ContractState, amount: u256, lock_timestamp: u64) {
            // Only owner can deposit
            assert(self.owner.read() == get_caller_address(), 'Only owner can deposit');
            
            // Validate amount
            assert(amount > 0, 'Amount must be greater than 0');
            
            // Check if already locked
            assert(!self.is_locked.read(), 'Piggy bank is already locked');
            
            // Validate lock timestamp (must be in the future)
            let current_timestamp = get_block_timestamp();
            assert(lock_timestamp > current_timestamp, 'Timestamp must be in the future');
            
            // Set lock timestamp and mark as locked
            self.lock_timestamp.write(lock_timestamp);
            self.is_locked.write(true);
            
            // Transfer tokens from owner to contract
            let token_dispatcher = self.token_dispatcher();
            token_dispatcher.transfer_from(get_caller_address(), get_contract_address(), amount);
            
            // Emit deposit event
            self.emit(Event::Deposit(DepositEvent {
                owner: get_caller_address(),
                amount,
                lock_timestamp,
            }));
        }

        fn withdraw(ref self: ContractState) {
            // Only owner can withdraw
            assert(self.owner.read() == get_caller_address(), 'Only owner can withdraw');
            
            // Check if piggy bank is locked
            assert(self.is_locked.read(), 'Piggy bank is not locked');
            
            // Check if lock period has passed
            let current_timestamp = get_block_timestamp();
            let lock_timestamp = self.lock_timestamp.read();
            assert(current_timestamp >= lock_timestamp, 'Lock period has not ended yet');
            
            // Get current balance
            let balance = self.get_current_balance();
            assert(balance > 0,'No tokens to withdraw');
            
            // Transfer all tokens to owner
            let token_dispatcher = self.token_dispatcher();
            token_dispatcher.transfer(get_caller_address(), balance);
            
            // Reset lock state
            self.is_locked.write(false);
            self.lock_timestamp.write(0);
            
            // Emit withdraw event
            self.emit(Event::Withdraw(WithdrawEvent {
                owner: get_caller_address(),
                amount: balance,
            }));
        }
    }

    // *************************************************************************
    //                            INTERNAL FUNCTIONS
    // *************************************************************************
    #[generate_trait]
    impl InternalImpl of InternalTrait {
        fn token_dispatcher(self: @ContractState) -> IERC20Dispatcher {
            IERC20Dispatcher {
                contract_address: 0x04718f5a0fc34cc1af16a1cdee98ffb20c31f5cd61d6ab07201858f4287c938d
                    .try_into()
                    .unwrap(),
            }
        }
    }
}
