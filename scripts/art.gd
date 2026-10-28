class_name Art
## Grafica scelta nel menu ("classica" o "reborn"): le pedine Reborn stanno in assets/reborn/tokens
## con lo stesso nome di quelle classiche; se una manca si usa la classica.
static var reborn := false
static func token(path: String) -> String:
	if reborn and path.begins_with("res://assets/tokens/"):
		var r := path.replace("res://assets/tokens/", "res://assets/reborn/tokens/")
		if ResourceLoader.exists(r):return r
	return path
