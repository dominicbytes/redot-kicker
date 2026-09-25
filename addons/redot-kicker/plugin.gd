@tool
extends EditorPlugin

const ClientClass = preload("res://addons/redot-kicker/kick_client.gd")
const SetupDialogClass = preload("res://addons/redot-kicker/editor/kick_setup_dialog.gd")
const CredentialExportClass = preload("res://addons/redot-kicker/editor/credential_helper_export.gd")
const MENU_LABEL: String = "Redot Kicker Setup"

var _setup_dialog: AcceptDialog = null
var _credential_export: EditorExportPlugin = null


func _enter_tree() -> void:
	add_custom_type("KickClient", "Node", ClientClass, null)
	_credential_export = CredentialExportClass.new()
	add_export_plugin(_credential_export)
	add_tool_menu_item(MENU_LABEL, _show_setup)


func _exit_tree() -> void:
	remove_tool_menu_item(MENU_LABEL)
	remove_custom_type("KickClient")
	if _credential_export != null:
		remove_export_plugin(_credential_export)
		_credential_export = null
	if is_instance_valid(_setup_dialog):
		_setup_dialog.queue_free()
	_setup_dialog = null


func _show_setup() -> void:
	if not is_instance_valid(_setup_dialog):
		_setup_dialog = SetupDialogClass.new()
		get_editor_interface().get_base_control().add_child(_setup_dialog)
	_setup_dialog.show_setup()
