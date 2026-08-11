@tool
extends AcceptDialog

const APP_GUIDE_URL: String = "https://docs.kick.com/getting-started/kick-apps-setup"
const OAUTH_GUIDE_URL: String = "https://docs.kick.com/getting-started/generating-tokens-oauth2-flow"
const EVENTS_GUIDE_URL: String = "https://docs.kick.com/events/introduction"


func _init() -> void:
	title = "Redot Kicker Setup"
	ok_button_text = "Close"
	min_size = Vector2i(700, 440)

	var content: VBoxContainer = VBoxContainer.new()
	content.add_theme_constant_override("separation", 12)
	add_child(content)

	var heading: Label = Label.new()
	heading.text = "Connect a developer-owned Kick application"
	heading.add_theme_font_size_override("font_size", 20)
	content.add_child(heading)

	var explanation: Label = Label.new()
	explanation.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	explanation.text = (
		"Each game developer or publisher owns one Kick application and self-hosts one single-tenant Redot Kicker relay. " +
		"The relay keeps the Kick client secret and OAuth tokens; the game stores only an opaque broker session in the operating-system credential vault."
	)
	content.add_child(explanation)

	_add_step(content, "1. Register a Kick application and configure the relay's HTTPS OAuth callback URL.")
	_add_step(content, "2. Deploy the reference-compatible relay for that one application; never put its client secret in the game.")
	_add_step(content, "3. Configure KickClient with the relay URL, publisher/application identifiers, a stable session slot, and minimum capabilities.")
	_add_step(content, "4. Ship the matching Windows or Linux x86-64 credential helper with the addon.")
	_add_step(content, "5. Publish privacy, retention, revocation, relay operations, and user-support details for the shipped game.")

	var warning: Label = Label.new()
	warning.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	warning.text = "Real-time events require the public relay. Without a healthy event downlink the client remains honestly available in REST_ONLY mode."
	content.add_child(warning)

	var links: HBoxContainer = HBoxContainer.new()
	links.add_theme_constant_override("separation", 16)
	content.add_child(links)
	_add_link(links, "Kick app setup", APP_GUIDE_URL)
	_add_link(links, "Kick OAuth", OAUTH_GUIDE_URL)
	_add_link(links, "Kick events", EVENTS_GUIDE_URL)


func show_setup() -> void:
	popup_centered()


func _add_step(parent: VBoxContainer, text: String) -> void:
	var label: Label = Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.text = text
	parent.add_child(label)


func _add_link(parent: HBoxContainer, text: String, url: String) -> void:
	var link: LinkButton = LinkButton.new()
	link.text = text
	link.pressed.connect(func() -> void: OS.shell_open(url))
	parent.add_child(link)
