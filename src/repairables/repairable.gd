class_name Repairable
extends Node2D


enum Type {
	TEST_FLAT_HEAD_SCREW_REPAIRABLE,
}

enum Mode {
	ENTERING,
	LEAVING,
	UNDER_REPAIR,
}

var mode := Mode.ENTERING
