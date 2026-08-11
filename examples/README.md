# Basic connection example

Open `basic_connection.tscn`, then set these non-secret inspector values on the root node:

- the HTTPS base URL of your self-hosted single-tenant Redot Kicker relay;
- your publisher identifier;
- your Kick application identifier;
- a stable session slot such as `primary`.

The example requests identity, channel/livestream, chat-write, and event capabilities. The relay—not the scene—owns the Kick client secret and OAuth tokens. The operating-system vault helper stores the opaque broker session after authorization.

The connection panel can authorize, restore, reconnect events, revoke, or clear local data. `send_example_message()` shows a typed outbound chat call, and `_on_chat_message()` consumes a typed `KickEvent`.
