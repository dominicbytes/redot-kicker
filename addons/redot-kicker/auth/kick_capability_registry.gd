class_name KickCapabilityRegistry
extends RefCounted

const InfoClass = preload("res://addons/redot-kicker/models/kick_capability_info.gd")

const SCOPE_USER_READ: String = "user:read"
const SCOPE_CHANNEL_READ: String = "channel:read"
const SCOPE_CHANNEL_WRITE: String = "channel:write"
const SCOPE_REWARDS_READ: String = "channel:rewards:read"
const SCOPE_REWARDS_WRITE: String = "channel:rewards:write"
const SCOPE_CHAT_WRITE: String = "chat:write"
const SCOPE_STREAMKEY_READ: String = "streamkey:read"
const SCOPE_EVENTS_SUBSCRIBE: String = "events:subscribe"
const SCOPE_MODERATION_BAN: String = "moderation:ban"
const SCOPE_CHAT_MANAGE: String = "moderation:chat_message:manage"
const SCOPE_KICKS_READ: String = "kicks:read"

const CAPABILITY_SCOPES: Dictionary = {
	"identity.read": [SCOPE_USER_READ],
	"channel.read": [SCOPE_CHANNEL_READ],
	"channel.manage": [SCOPE_CHANNEL_WRITE],
	"categories.read": [],
	"livestreams.read": [],
	"chat.write": [SCOPE_CHAT_WRITE],
	"chat.delete": [SCOPE_CHAT_MANAGE],
	"events.receive": [SCOPE_EVENTS_SUBSCRIBE],
	"events.manage": [SCOPE_EVENTS_SUBSCRIBE],
	"rewards.read": [SCOPE_REWARDS_READ],
	"rewards.manage": [SCOPE_REWARDS_WRITE],
	"moderation.ban": [SCOPE_MODERATION_BAN],
	"kicks.read": [SCOPE_KICKS_READ],
	"streamkey.read": [SCOPE_STREAMKEY_READ],
}

const OPERATIONS: Dictionary = {
	"categories.search.v2": {"capability":"categories.read","method":"GET","path":"/public/v2/categories","scopes":[],"token_kinds":["user","app"]},
	"categories.search.v1": {"capability":"categories.read","method":"GET","path":"/public/v1/categories","scopes":[],"token_kinds":["user","app"],"deprecated":true},
	"categories.get.v1": {"capability":"categories.read","method":"GET","path":"/public/v1/categories/{category_id}","scopes":[],"token_kinds":["user","app"],"deprecated":true},
	"channels.get": {"capability":"channel.read","method":"GET","path":"/public/v1/channels","scopes":[SCOPE_CHANNEL_READ],"token_kinds":["user","app"]},
	"channels.update": {"capability":"channel.manage","method":"PATCH","path":"/public/v1/channels","scopes":[SCOPE_CHANNEL_WRITE],"token_kinds":["user"],"write":true,"confirm":true},
	"rewards.list": {"capability":"rewards.read","method":"GET","path":"/public/v1/channels/rewards","scopes":[SCOPE_REWARDS_READ,SCOPE_REWARDS_WRITE],"scope_mode":"any","token_kinds":["user"]},
	"rewards.create": {"capability":"rewards.manage","method":"POST","path":"/public/v1/channels/rewards","scopes":[SCOPE_REWARDS_WRITE],"token_kinds":["user"],"write":true,"confirm":true},
	"rewards.update": {"capability":"rewards.manage","method":"PATCH","path":"/public/v1/channels/rewards/{id}","scopes":[SCOPE_REWARDS_WRITE],"token_kinds":["user"],"write":true,"confirm":true},
	"rewards.delete": {"capability":"rewards.manage","method":"DELETE","path":"/public/v1/channels/rewards/{id}","scopes":[SCOPE_REWARDS_WRITE],"token_kinds":["user"],"write":true,"confirm":true},
	"redemptions.list": {"capability":"rewards.read","method":"GET","path":"/public/v1/channels/rewards/redemptions","scopes":[SCOPE_REWARDS_READ,SCOPE_REWARDS_WRITE],"scope_mode":"any","token_kinds":["user"]},
	"redemptions.accept": {"capability":"rewards.manage","method":"POST","path":"/public/v1/channels/rewards/redemptions/accept","scopes":[SCOPE_REWARDS_WRITE],"token_kinds":["user"],"write":true,"confirm":true},
	"redemptions.reject": {"capability":"rewards.manage","method":"POST","path":"/public/v1/channels/rewards/redemptions/reject","scopes":[SCOPE_REWARDS_WRITE],"token_kinds":["user"],"write":true,"confirm":true},
	"chat.send": {"capability":"chat.write","method":"POST","path":"/public/v1/chat","scopes":[SCOPE_CHAT_WRITE],"token_kinds":["user"],"write":true},
	"chat.delete": {"capability":"chat.delete","method":"DELETE","path":"/public/v1/chat/{message_id}","scopes":[SCOPE_CHAT_MANAGE],"token_kinds":["user"],"write":true,"confirm":true},
	"subscriptions.list": {"capability":"events.manage","method":"GET","path":"/public/v1/events/subscriptions","scopes":[],"token_kinds":["user","app"],"relay":true},
	"subscriptions.create": {"capability":"events.manage","method":"POST","path":"/public/v1/events/subscriptions","scopes":[SCOPE_EVENTS_SUBSCRIBE],"token_kinds":["user","app"],"write":true,"relay":true},
	"subscriptions.delete": {"capability":"events.manage","method":"DELETE","path":"/public/v1/events/subscriptions","scopes":[SCOPE_EVENTS_SUBSCRIBE],"token_kinds":["user","app"],"write":true,"confirm":true,"relay":true},
	"kicks.leaderboard": {"capability":"kicks.read","method":"GET","path":"/public/v1/kicks/leaderboard","scopes":[SCOPE_KICKS_READ],"token_kinds":["user"]},
	"livestreams.list.v2": {"capability":"livestreams.read","method":"GET","path":"/public/v2/livestreams","scopes":[],"token_kinds":["user","app"]},
	"livestreams.list.v1": {"capability":"livestreams.read","method":"GET","path":"/public/v1/livestreams","scopes":[],"token_kinds":["user","app"],"deprecated":true},
	"livestreams.by_users": {"capability":"livestreams.read","method":"GET","path":"/public/v1/users/livestreams","scopes":[],"token_kinds":["user","app"]},
	"livestreams.stats": {"capability":"livestreams.read","method":"GET","path":"/public/v1/livestreams/stats","scopes":[],"token_kinds":["user","app"]},
	"moderation.ban": {"capability":"moderation.ban","method":"POST","path":"/public/v1/moderation/bans","scopes":[SCOPE_MODERATION_BAN],"token_kinds":["user"],"write":true,"confirm":true},
	"moderation.unban": {"capability":"moderation.ban","method":"DELETE","path":"/public/v1/moderation/bans","scopes":[SCOPE_MODERATION_BAN],"token_kinds":["user"],"write":true,"confirm":true},
	"public_key.get": {"capability":"events.receive","method":"GET","path":"/public/v1/public-key","scopes":[],"token_kinds":["none"],"relay":true},
	"token.introspect": {"capability":"identity.read","method":"POST","path":"/oauth/token/introspect","scopes":[],"token_kinds":["user","app"]},
	"users.get": {"capability":"identity.read","method":"GET","path":"/public/v1/users","scopes":[SCOPE_USER_READ],"token_kinds":["user","app"]},
	"stream_key.get": {"capability":"streamkey.read","method":"GET","path":"","scopes":[SCOPE_STREAMKEY_READ],"token_kinds":["user"],"availability":"scope_declared_route_unavailable"},
}


static func operation_info(operation_id: String) -> KickCapabilityInfo:
	var definition: Variant = OPERATIONS.get(operation_id, {})
	return null if not definition is Dictionary or definition.is_empty() else InfoClass.from_definition(operation_id, definition)


static func all_operation_info() -> Array[KickCapabilityInfo]:
	var ids: Array = OPERATIONS.keys()
	ids.sort()
	var result: Array[KickCapabilityInfo] = []
	for id_value: Variant in ids:
		result.append(operation_info(str(id_value)))
	return result


static func all_capabilities() -> PackedStringArray:
	var result: PackedStringArray = PackedStringArray()
	for capability: Variant in CAPABILITY_SCOPES:
		result.append(str(capability))
	result.sort()
	return result


static func validate_capabilities(capabilities: PackedStringArray) -> KickApiError:
	if capabilities.is_empty():
		return KickApiError.invalid("At least one Kick capability is required")
	for capability: String in capabilities:
		if not CAPABILITY_SCOPES.has(capability):
			return KickApiError.invalid("Unknown Kick capability: %s" % capability)
	return null


static func scopes_for(capabilities: PackedStringArray) -> PackedStringArray:
	if validate_capabilities(capabilities) != null:
		return PackedStringArray()
	var unique: Dictionary = {}
	for capability: String in capabilities:
		for scope: String in CAPABILITY_SCOPES[capability]:
			unique[scope] = true
	var values: Array = unique.keys()
	values.sort()
	var result: PackedStringArray = PackedStringArray()
	for value: Variant in values:
		result.append(str(value))
	return result
