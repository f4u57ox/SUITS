module object_display::chat {
    use sui::object::{Self, UID, ID};
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};
    use std::vector::length;

    use sui::dynamic_object_field::{Self};
    use sui::sui::SUI;
    use sui::balance::{Self, Balance};
    
    use std::debug;

    use sui::event::emit;

    /// Max text length.
    const MAX_TEXT_LENGTH: u64 = 512;

    /// Text size overflow.
    const ETextOverflow: u64 = 0;

    // ======== Events =========

    /// Event. When a new chat has been created.
    struct ChatShopCreated has copy, drop { id: ID }
    struct ChatTopMessageCreated has copy, drop { id: ID, top_response_id: ID }
    struct ChatResponseCreated has copy, drop { id: ID, top_message_id: ID, seq_n: u64 }

    /// Capability that grants an owner the right to collect profits.
    struct ChatOwnerCap has key { id: UID }

    /// A shared object. `key` ability is required.
    struct ChatShop has key {
        id: UID,
        price: u64,
        balance: Balance<SUI>
    }

    struct ChatTopMessage has key, store {
        id: UID,
        chat_shop_id: ID,
        chat_top_response_id: ID,
        author: address,
        responses_count: u64,
    }

    struct ChatResponse has key, store {
        id: UID,
        chat_top_message_id: ID,
        author: address,
        text: vector<u8>,
        metadata: vector<u8>,
        seq_n: u64, // n of message in thread
    }

    /// Estructura para los mensajes privados
    struct PrivateMessage has key, store {
        id: UID,
        sender: address,
        recipient: address,
        encrypted_text: vector<u8>,
    }

    // Init function is often ideal place for initializing
    // a shared object as it is called only once.
    //
    // To share an object `transfer::share_object` is used.
    fun init(ctx: &mut TxContext) {
        transfer::transfer(ChatOwnerCap {
            id: object::new(ctx)
        }, tx_context::sender(ctx));

        let id = object::new(ctx);
        emit(ChatShopCreated { id: object::uid_to_inner(&id) });

        // Share the object to make it accessible to everyone!
        transfer::share_object(ChatShop {
            id: id,
            price: 1000,
            balance: balance::zero()
        })
    }

    /// Mint (post) a chatMessage object without referencing another object.
    public entry fun post(
        chat_shop: &ChatShop,
        text: vector<u8>,
        metadata: vector<u8>,
        ctx: &mut TxContext,
    ) {
        assert!(length(&text) <= MAX_TEXT_LENGTH, ETextOverflow);
        let id = object::new(ctx);
        let chat_response_id = object::new(ctx);

        emit(ChatTopMessageCreated { id: object::uid_to_inner(&id), top_response_id: object::uid_to_inner(&chat_response_id) });
        emit(ChatResponseCreated { id: object::uid_to_inner(&chat_response_id), top_message_id: object::uid_to_inner(&id), seq_n: 0 });

        let chat_top_message = ChatTopMessage {
            id: id,
            chat_shop_id: object::id(chat_shop),
            author: tx_context::sender(ctx),
            chat_top_response_id: object::uid_to_inner(&chat_response_id),
            responses_count: 0,
        };

        let chat_response = ChatResponse {
            id: chat_response_id,
            chat_top_message_id: object::id(&chat_top_message),
            author: tx_context::sender(ctx),
            text: text,
            metadata,
            seq_n: 0,
        };
        dynamic_object_field::add(&mut chat_top_message.id, b"as_chat_response", chat_response);

        transfer::share_object(chat_top_message);
    }

    public entry fun reply(
        chat_top_message: &mut ChatTopMessage,
        text: vector<u8>,
        metadata: vector<u8>,
        ctx: &mut TxContext,
    ) {
        assert!(length(&text) <= MAX_TEXT_LENGTH, ETextOverflow);

        let dynamic_field_exists = dynamic_object_field::exists_(&chat_top_message.id, b"as_chat_response");
        if (dynamic_field_exists) {
            let top_level_chat_response = dynamic_object_field::remove<vector<u8>, ChatResponse>(&mut chat_top_message.id, b"as_chat_response");
            transfer::transfer(top_level_chat_response, chat_top_message.author);
        };

        chat_top_message.responses_count = chat_top_message.responses_count + 1;

        let id = object::new(ctx);

        emit(ChatResponseCreated { id: object::uid_to_inner(&id), top_message_id: object::uid_to_inner(&chat_top_message.id), seq_n: chat_top_message.responses_count });

        let chat_response = ChatResponse {
            id: id,
            chat_top_message_id: object::id(chat_top_message),
            author: tx_context::sender(ctx),
            text: text,
            metadata,
            seq_n: chat_top_message.responses_count,
        };

        transfer::transfer(chat_response, tx_context::sender(ctx));
    }

    /// Función para enviar un mensaje privado
    public entry fun send_message(
        recipient: address,
        encrypted_text: vector<u8>,
        ctx: &mut TxContext
    ) {
        assert!(length(&encrypted_text) <= MAX_TEXT_LENGTH, ETextOverflow);
        
        let id = object::new(ctx);
        let message = PrivateMessage {
            id: id,
            sender: tx_context::sender(ctx),
            recipient: recipient,
            encrypted_text: encrypted_text,
        };

        transfer::transfer(message, recipient);
    }

   
