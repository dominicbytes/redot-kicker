class_name KickKicksService
extends RefCounted

var _api: KickApiClient


func _init(api: KickApiClient) -> void:
	_api = api


func leaderboard(top: int = 10, cancellation: KickCancellationToken = null) -> KickApiResult:
	if top < 1 or top > 100:
		var failed: KickApiResult = KickApiResult.new()
		failed.error = KickApiError.invalid("KICKs leaderboard size must be between 1 and 100")
		return failed
	return KickModelMapper.map_result(await _api.invoke("kicks.leaderboard", {"top": top}, {}, {}, false, "", cancellation), "kicks_leaderboard")
