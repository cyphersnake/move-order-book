module orderbook::orderbook {
    use std::vector;

    use sui::math;
    use sui::object::{Self, UID};
    use sui::tx_context::{TxContext, Self};
    use sui::coin::{Self, Coin};
    use sui::balance::{Balance, Self};
    use orderbook::priority_queue::{Self, PriorityQueue};
    use sui::transfer;

    // Error constant for zero quantity bid or ask orders
    const EZeroAmountProhibited: u64 = 0;

    fun init(_: &mut TxContext) {}

    // Offer struct represents an offer in the order book with 
    // a execution beneficiary and staked amount:
    // For bids it's base token
    // For asks it's quote token
    //
    // Type of staked token fixed in `T` generic param
    struct Offer<phantom T> has store, drop {
        beneficiary: address,
        staked: u64
    }

    public fun offer_staked<T>(offer: &Offer<T>): &u64 {
        &offer.staked
    }

    // Pair struct represents a trading pair with bids, asks, and balances for each asset
    struct Pair<phantom B, phantom Q> has key, store {
        id: UID,
        bids: PriorityQueue<Offer<B>>,
        asks: PriorityQueue<Offer<Q>>,

        // The base token balance locked in the trading pair. 
        // 
        // Due to the priority queue that `drop` requires,
        // I had to allocate the entire balance here and 
        // use only the `staked` from `Offer<B>` for balance check
        base_balance: Balance<B>,

        // The quote token balance locked in the trading pair. 
        //
        // Due to the priority queue that `drop` requires,
        // I had to allocate the entire balance here and 
        // use only the `staked` from `Offer<Q>` for balance check
        quote_balance: Balance<Q>,
    }

    // Create a new trading pair and share the object
    public fun create_pair<B, Q>(ctx: &mut TxContext) {
        let pair = Pair {
            id: object::new(ctx),
            bids: priority_queue::new<Offer<B>>(vector::empty()),
            asks: priority_queue::new<Offer<Q>>(vector::empty()),
            base_balance: balance::zero<B>(),
            quote_balance: balance::zero<Q>(),
        };

        transfer::share_object(pair);
    }

    // Submit an bid order to the trading pair
    public fun submit_bid<B, Q>(
        ctx: &mut TxContext,
        pair: &mut Pair<B, Q>,
        price: u64,
        quantity: Coin<B>
    ) {
        let quantity_amount =  coin::value(&quantity);
        assert!(quantity_amount > 0, EZeroAmountProhibited);

        push_bid(pair, price, tx_context::sender(ctx), coin::into_balance(quantity));

        match_orders(ctx, pair)
    }

    // Submit an ask order to the trading pair
    public fun submit_ask<B, Q>(
        ctx: &mut TxContext,
        pair: &mut Pair<B, Q>,
        price: u64,
        quantity: Coin<Q>,
    ) {
        let quantity_amount =  coin::value(&quantity);
        assert!(quantity_amount > 0, EZeroAmountProhibited);

        push_ask(pair, price, tx_context::sender(ctx), coin::into_balance(quantity));

        match_orders(ctx, pair)
    }

    // Get the asks from the trading pair
    public fun asks<B, Q>(pair: &Pair<B, Q>): &PriorityQueue<Offer<Q>> {
        &pair.asks
    }

    // Get the bids from the trading pair
    public fun bids<B, Q>(pair: &Pair<B, Q>): &PriorityQueue<Offer<B>> {
        &pair.bids
    }

    fun push_ask<B, Q>(pair: &mut Pair<B, Q>, price: u64, beneficiary: address, quantity: Balance<Q>) {
        let ask_offer: Offer<Q> = Offer {
            beneficiary,
            staked: balance::value(&quantity),
        };
        balance::join(&mut pair.quote_balance, quantity);
        priority_queue::insert(&mut pair.asks, reverse_ask_price(price), ask_offer);
    }

    fun push_bid<B, Q>(pair: &mut Pair<B, Q>, price: u64, beneficiary: address, quantity: Balance<B>) {
        let ask_offer: Offer<B> = Offer {
            beneficiary,
            staked: balance::value(&quantity),
        };
        balance::join(&mut pair.base_balance, quantity);
        priority_queue::insert(&mut pair.bids, price, ask_offer);
    }

    fun pop_min_ask<B, Q>(pair: &mut Pair<B, Q>): (u64, address, Balance<Q>) {
        let (ask_price, min_ask) = priority_queue::pop_max(&mut pair.asks);
        (reverse_ask_price(ask_price), min_ask.beneficiary, balance::split(&mut pair.quote_balance, min_ask.staked))
    }

    fun pop_max_bid<B, Q>(pair: &mut Pair<B, Q>): (u64, address, Balance<B>) {
        let (bid_price, max_bid) = priority_queue::pop_max(&mut pair.bids);
        (bid_price, max_bid.beneficiary, balance::split(&mut pair.base_balance, max_bid.staked))
    }

    // Match orders in the order book, executing trades if bid and ask prices match
    // TODO Optimise so that new orders are not added, but run through here first
    fun match_orders<B, Q>(ctx: &mut TxContext, pair: &mut Pair<B, Q>) {
        while (!priority_queue::is_empty(&pair.asks) && !priority_queue::is_empty(&pair.bids)) {
            let (ask_price, ask_beneficiary, ask_balance) = pop_min_ask(pair);
            let (bid_price, bid_beneficiary, bid_balance) = pop_max_bid(pair);

            if (bid_price >= ask_price) {
                let bid_quote_quantity = balance::value(&bid_balance) * ask_price;
                let ask_quote_quantity = balance::value(&ask_balance);

                let quote_match_quantity = math::min(bid_quote_quantity, ask_quote_quantity);
                let base_match_quantity = quote_match_quantity / ask_price;

                let base_trade = balance::split(&mut bid_balance, base_match_quantity);
                let quote_trade = balance::split(&mut ask_balance, quote_match_quantity);

                transfer::transfer(
                    coin::from_balance(base_trade, ctx),
                    ask_beneficiary
                );

                transfer::transfer(
                    coin::from_balance(quote_trade, ctx),
                    bid_beneficiary
                );

                if (balance::value(&bid_balance) != 0) {
                    push_bid(pair, bid_price, bid_beneficiary, bid_balance);
                } else {
                    balance::destroy_zero(bid_balance);
                };

                if (balance::value(&ask_balance) != 0) {
                    push_ask(pair, ask_price, ask_beneficiary, ask_balance);
                } else {
                    balance::destroy_zero(ask_balance);
                };
            } else {
                push_bid(pair, bid_price, bid_beneficiary, bid_balance);
                push_ask(pair, ask_price, ask_beneficiary, ask_balance);
                break
            }
        }
    }

    #[test_only]
    public fun init_for_testing(ctx: &mut TxContext) {
        init(ctx)
    }

    // TODO Find u64::MAX constant or figure out why the self-written `const` doesn't work
    fun reverse_ask_price(price: u64): u64 {
        18446744073709551615 - price
    }
}

#[test_only] 
module orderbook::tests {
    use std::vector;

    use sui::test_scenario::{Self as test, Scenario, next_tx, ctx};
    use sui::coin::{Self, mint_for_testing as mint};

    use orderbook::priority_queue;
    use orderbook::orderbook;

    fun people(): (address, address, address) { (@0xBEEF, @0xBEEE, @0x1337) }
    fun scenario(): Scenario { test::begin(@0x1) }

    struct BASE {}
    struct QUOTE {}

    // TODO Find u64::MAX constant or figure out why the self-written `const` doesn't work
    fun reverse_ask_price(price: u64): u64 {
        18446744073709551615 - price
    }

    fun base_init(): (Scenario, address, address, address) {
        let scenario = scenario();
        let (admin, buyer, seller) = people();

        next_tx(&mut scenario, admin);
        {
            orderbook::orderbook::init_for_testing(ctx(&mut scenario));
            orderbook::create_pair<BASE, QUOTE>(
                ctx(&mut scenario)
            );
        };

        (scenario, admin, buyer, seller)
    }

    #[test]
    fun best_choose_quote() {
        let (scenario, admin, _buyer, seller) = base_init();

        let first = @0xF100;
        let second = @0xF200;
        let third = @0xF300;

        next_tx(&mut scenario, first);
        {
            let pair = test::take_shared<orderbook::Pair<BASE, QUOTE>>(&mut scenario);

            let base_quantity = mint<BASE>(1000, ctx(&mut scenario));
            orderbook::submit_bid<BASE, QUOTE>(
                ctx(&mut scenario),
                &mut pair,
                40,
                base_quantity,
            );
            test::return_shared(pair);
        };

        next_tx(&mut scenario, second);
        {
            let pair = test::take_shared<orderbook::Pair<BASE, QUOTE>>(&mut scenario);
            let base_quantity = mint<BASE>(10000, ctx(&mut scenario));
            orderbook::submit_bid<BASE, QUOTE>(
                ctx(&mut scenario),
                &mut pair,
                20,
                base_quantity,
            );
            test::return_shared(pair);
        };

        next_tx(&mut scenario, third);
        {
            let pair = test::take_shared<orderbook::Pair<BASE, QUOTE>>(&mut scenario);
            let base_quantity = mint<BASE>(100000, ctx(&mut scenario));
            orderbook::submit_bid<BASE, QUOTE>(
                ctx(&mut scenario),
                &mut pair,
                10,
                base_quantity,
            );

            assert!(priority_queue::length(orderbook::bids(&pair)) == 3, 0);
            assert!(priority_queue::length(orderbook::asks(&pair)) == 0, 0);

            test::return_shared(pair);
        };

        next_tx(&mut scenario, seller);
        {
            let pair = test::take_shared<orderbook::Pair<BASE, QUOTE>>(&mut scenario);

            let quantity = mint<QUOTE>(1000000, ctx(&mut scenario));
            orderbook::submit_ask<BASE, QUOTE>(
                ctx(&mut scenario),
                &mut pair,
                5,
                quantity,
            );

            assert!(priority_queue::length(orderbook::bids(&pair)) == 0, 0);
            assert!(priority_queue::length(orderbook::asks(&pair)) == 1, 0);

            test::return_shared(pair);
        };

        next_tx(&mut scenario, admin);
        {
            let seller_coins = test::ids_for_address<sui::coin::Coin<BASE>>(seller);
            assert!(vector::length(&seller_coins) == 3, 0);
            let last_trade = test::take_from_address_by_id<sui::coin::Coin<BASE>>(
                &mut scenario,
                seller,
                vector::pop_back(&mut seller_coins)
            );
            assert!(coin::value(&last_trade) == 100000, 0);
            test::return_to_address(seller, last_trade);

            let mid_trade = test::take_from_address_by_id<sui::coin::Coin<BASE>>(
                &mut scenario,
                seller,
                vector::pop_back(&mut seller_coins)
            );
            assert!(coin::value(&mid_trade) == 10000, 0);
            test::return_to_address(seller, mid_trade);

            let first_trade = test::take_from_address_by_id<sui::coin::Coin<BASE>>(
                &mut scenario,
                seller,
                vector::pop_back(&mut seller_coins)
            );
            assert!(coin::value(&first_trade) == 1000, 0);
            test::return_to_address(seller, first_trade);

            let pair = test::take_shared<orderbook::Pair<BASE, QUOTE>>(&mut scenario);
            let (price, offer) = priority_queue::borrow(orderbook::asks(&pair), 0);
            let last_ask_staked = orderbook::offer_staked(offer);

            assert!(*price == reverse_ask_price(5), 0);
            assert!(*last_ask_staked == 445000, 0);

            test::return_shared(pair);
        };

        test::end(scenario);
    }

    #[test]
    fun not_match() {
        let (scenario, _admin, buyer, seller) = base_init();

        next_tx(&mut scenario, buyer);
        {
            let pair = test::take_shared<orderbook::Pair<BASE, QUOTE>>(&mut scenario);

            let base_quantity = mint<BASE>(1000, ctx(&mut scenario));
            orderbook::submit_bid<BASE, QUOTE>(
                ctx(&mut scenario),
                &mut pair,
                40,
                base_quantity,
            );
            assert!(priority_queue::length(orderbook::bids(&pair)) == 1, 0);
            assert!(priority_queue::length(orderbook::asks(&pair)) == 0, 0);

            test::return_shared(pair);
        };

        next_tx(&mut scenario, seller);
        {
            let pair = test::take_shared<orderbook::Pair<BASE, QUOTE>>(&mut scenario);

            let quantity = mint<QUOTE>(25, ctx(&mut scenario));
            orderbook::submit_ask<BASE, QUOTE>(
                ctx(&mut scenario),
                &mut pair,
                50,
                quantity,
            );

            assert!(priority_queue::length(orderbook::bids(&pair)) == 1, 0);
            assert!(priority_queue::length(orderbook::asks(&pair)) == 1, 0);

            test::return_shared(pair);
        };

        test::end(scenario);
    }

    #[test]
    fun base_trade() {
        let (scenario, admin, buyer, seller) = base_init();

        next_tx(&mut scenario, buyer);
        {
            let pair = test::take_shared<orderbook::Pair<BASE, QUOTE>>(&mut scenario);

            let base_quantity = mint<BASE>(100, ctx(&mut scenario));
            orderbook::submit_bid<BASE, QUOTE>(
                ctx(&mut scenario),
                &mut pair,
                4,
                base_quantity,
            );
            assert!(priority_queue::length(orderbook::bids(&pair)) == 1, 0);
            assert!(priority_queue::length(orderbook::asks(&pair)) == 0, 0);

            test::return_shared(pair);
        };

        next_tx(&mut scenario, seller);
        {
            let pair = test::take_shared<orderbook::Pair<BASE, QUOTE>>(&mut scenario);

            let quantity = mint<QUOTE>(100, ctx(&mut scenario));
            orderbook::submit_ask<BASE, QUOTE>(
                ctx(&mut scenario),
                &mut pair,
                2,
                quantity,
            );

            assert!(priority_queue::length(orderbook::bids(&pair)) == 1, 0);
            assert!(priority_queue::length(orderbook::asks(&pair)) == 0, 0);

            test::return_shared(pair);
        };

        next_tx(&mut scenario, admin);
        {
            assert!(vector::length(&test::ids_for_address<sui::coin::Coin<QUOTE>>(buyer)) == 1, 0);
            assert!(vector::length(&test::ids_for_address<sui::coin::Coin<BASE>>(seller)) == 1, 0);

            let buyer_quote_coin = test::take_from_address<sui::coin::Coin<QUOTE>>(&mut scenario, buyer);
            let seller_base_coin = test::take_from_address<sui::coin::Coin<BASE>>(&mut scenario, seller);

            assert!(coin::value(&buyer_quote_coin) == 100, 0);
            assert!(coin::value(&seller_base_coin) == 50, 0);

            test::return_to_address(seller, seller_base_coin);
            test::return_to_address(buyer, buyer_quote_coin);
        };

        next_tx(&mut scenario, seller);
        {
            let pair = test::take_shared<orderbook::Pair<BASE, QUOTE>>(&mut scenario);

            let quantity = mint<QUOTE>(200, ctx(&mut scenario));
            orderbook::submit_ask<BASE, QUOTE>(
                ctx(&mut scenario),
                &mut pair,
                4,
                quantity,
            );

            assert!(priority_queue::length(orderbook::asks(&pair)) == 0, 0);
            assert!(priority_queue::length(orderbook::bids(&pair)) == 0, 0);

            test::return_shared(pair);
        };

        next_tx(&mut scenario, admin);
        {
            assert!(vector::length(&test::ids_for_address<sui::coin::Coin<QUOTE>>(buyer)) == 2, 0);
            assert!(vector::length(&test::ids_for_address<sui::coin::Coin<BASE>>(seller)) == 2, 0);

            let buyer_quote_coin = test::take_from_address<sui::coin::Coin<QUOTE>>(&mut scenario, buyer);
            let seller_base_coin = test::take_from_address<sui::coin::Coin<BASE>>(&mut scenario, seller);

            let buyer_quote_coin_val = coin::value(&buyer_quote_coin);
            let seller_base_coin_val = coin::value(&seller_base_coin);

            assert!(buyer_quote_coin_val == 200, 0);
            assert!(seller_base_coin_val == 50, 0);

            test::return_to_address(seller, seller_base_coin);
            test::return_to_address(buyer, buyer_quote_coin);
        };

        test::end(scenario);
    }
}
