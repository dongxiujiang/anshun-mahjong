extends RefCounted
## 4000 局风险标定得到的单调查找表。
## 校准概率来自分桶实际点炮率；损失按对手最高听牌概率分桶。

const PROBABILITY_BOUNDS := [0.0, 0.005, 0.01, 0.02, 0.04, 0.08, 0.3200001, 1.0000001]
const CALIBRATED_PROBABILITY := [0.0005, 0.0028, 0.0104, 0.0129, 0.0246, 0.0433, 0.0433]
const STRENGTH_BOUNDS := [0.0, 0.2, 0.8, 1.0000001]
const LOSS_BY_STRENGTH := [13.0, 18.56, 27.01]

static func probability(raw: float) -> float:
	var value := clampf(raw, 0.0, 1.0)
	for index in CALIBRATED_PROBABILITY.size():
		if value < float(PROBABILITY_BOUNDS[index + 1]):
			return float(CALIBRATED_PROBABILITY[index])
	return float(CALIBRATED_PROBABILITY[-1])

static func expected_loss(raw_probability: float, strength: float) -> float:
	return probability(raw_probability) * loss(strength)

static func loss(strength: float) -> float:
	var value := clampf(strength, 0.0, 1.0)
	for index in LOSS_BY_STRENGTH.size():
		if value < float(STRENGTH_BOUNDS[index + 1]):
			return float(LOSS_BY_STRENGTH[index])
	return float(LOSS_BY_STRENGTH[-1])
