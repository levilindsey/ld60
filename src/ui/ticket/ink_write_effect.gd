extends RichTextEffect
## A RichTextLabel effect that writes text in by hand: `[ink]...[/ink]`.
## Each letter fades in and settles as `progress` passes it, so the line
## appears letter by letter like ink from a pen.


## How far a letter rises while it fades in, in pixels.
const _SETTLE_PX := 3.0

var bbcode := "ink"
## How many letters are written so far. A fractional part fades in the
## next letter.
var progress := 0.0
## How many letters a single letter's fade spans.
var fade_letters := 1.5


func _process_custom_fx(char_fx: CharFXTransform) -> bool:
	var amount := clampf(
		(progress - char_fx.relative_index) / fade_letters,
		0.0,
		1.0,
	)
	char_fx.color.a *= amount
	char_fx.offset.y += (1.0 - amount) * _SETTLE_PX
	return true
