extends SceneTree

const TARGET: String = "redot-kicker/test/credential-helper-smoke"
const TEST_VALUE: String = "opaque-broker-session-test-value"

var _failures: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var helper: KickCredentialHelperClient = KickCredentialHelperClient.new()
	await helper.delete(TARGET)
	var ping: KickCredentialResult = await helper.ping()
	_check(ping.is_success(), "ping")
	var stored: KickCredentialResult = await helper.store(TARGET, TEST_VALUE)
	_check(stored.is_success(), "store")
	var read: KickCredentialResult = await helper.read(TARGET)
	var matched: bool = read.is_success() and read.secret == TEST_VALUE
	read.clear_secret()
	_check(matched, "read")
	var deleted: KickCredentialResult = await helper.delete(TARGET)
	_check(deleted.is_success() or deleted.status == "not_found", "delete")
	var missing: KickCredentialResult = await helper.read(TARGET)
	_check(missing.status == "not_found", "read after delete")
	print("KICKER CREDENTIAL HELPER: %s" % ("PASS" if _failures == 0 else "FAIL (%d)" % _failures))
	quit(0 if _failures == 0 else 1)


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS: " + label)
	else:
		_failures += 1
		print("FAIL: " + label)
