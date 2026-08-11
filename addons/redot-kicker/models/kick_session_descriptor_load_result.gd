class_name KickSessionDescriptorLoadResult
extends RefCounted

var descriptor: KickSessionDescriptor = null
var error: KickApiError = null


func is_success() -> bool:
	return descriptor != null and error == null
