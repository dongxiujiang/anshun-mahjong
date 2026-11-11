"""Upper bound with arbitrary pong chains, including four upstream pongs.

Relaxing tile identities permits more claims than a real 108-tile game. A kong
uses a meld slot and an extra wall tile, so cannot beat the corresponding pong.
Claimed discards leave their owner's river. Chickens count toward the same bound.
"""
from functools import lru_cache
import unittest


@lru_cache(None)
def max_retained_discards(wall_left, melds, discarder):
    # Seat 0 is the observed player. The current player already holds a tile
    # to discard; only an unclaimed discard remains in that player's river.
    retained = int(discarder == 0)
    best = retained + (max_retained_discards(wall_left - 1, melds, (discarder - 1) % 4)
                       if wall_left else 0)
    for claimant in range(4):
        if claimant == discarder or melds[claimant] == 4:
            continue
        claimed = list(melds)
        claimed[claimant] += 1
        best = max(best, max_retained_discards(wall_left, tuple(claimed), claimant))
    return best


class RiverCapacityTest(unittest.TestCase):
    def test_all_dealers_and_all_claim_chains_fit_twenty_slots(self):
        # 108 - 4*13 - the dealer's initial draw = 55 remaining draws.
        for dealer in range(4):
            with self.subTest(dealer=dealer):
                self.assertEqual(max_retained_discards(55, (0, 0, 0, 0), dealer), 20)


if __name__ == "__main__":
    unittest.main()
