class_name KickApiClient
extends RefCounted

signal rate_limit_observed(operation_id: String, remaining: int, reset_unix: int, retry_after_seconds: float)

var _auth: KickAuthManager = null
var _gate: KickCapabilityGate = null


func configure(auth: KickAuthManager, gate: KickCapabilityGate) -> KickApiError:
	if auth == null or gate == null:
		return KickApiError.invalid("Kick authentication and capability gate are required")
	_auth = auth
	_gate = gate
	return null


func invoke(
	operation_id: String,
	query: Dictionary = {},
	path_parameters: Dictionary = {},
	body: Dictionary = {},
	confirmed: bool = false,
	idempotency_key: String = "",
	cancellation: KickCancellationToken = null
) -> KickApiResult:
	var gate_error: KickApiError = _gate.require_operation(operation_id, confirmed)
	if gate_error != null:
		return _failed(gate_error)
	var info: KickCapabilityInfo = KickCapabilityRegistry.operation_info(operation_id)
	var result: KickApiResult = await _auth.invoke(
		operation_id,
		query,
		path_parameters,
		body,
		confirmed,
		idempotency_key,
		cancellation,
		not info.is_write
	)
	if result != null and (result.rate_limit_remaining >= 0 or result.retry_after_seconds > 0.0):
		rate_limit_observed.emit(operation_id, result.rate_limit_remaining, result.rate_limit_reset_unix, result.retry_after_seconds)
	return result


func _failed(error: KickApiError) -> KickApiResult:
	var result: KickApiResult = KickApiResult.new()
	result.error = error
	return result
