extends RefCounted

enum Seat { EAST, SOUTH, WEST, NORTH }
const ASSIGNMENT_ORDER := [Seat.SOUTH, Seat.EAST, Seat.NORTH, Seat.WEST]

static func next(seat: int) -> int:
	return posmod(seat - 1, 4)

static func previous(seat: int) -> int:
	return posmod(seat + 1, 4)

static func opposite(seat: int) -> int:
	return posmod(seat + 2, 4)

static func relative(owner: int, other: int) -> int:
	return posmod(owner - other, 4)
