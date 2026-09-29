class_name Combat
# Sorteios do dano como na wiki (Damage, Critical hit): variância de ±15% sobre o dano da arma, antes da defesa, e crítico de 4% que dobra o
# dano depois da defesa e dá 40% mais recuo. Aqui só se sorteia; quem desconta a defesa é o hurt() de enemy.gd e de player.gd.

const CRIT := 0.04              # chance base de crítico das armas
const SPREAD := 0.15
const CRIT_KNOCKBACK := 1.4


# O dano depois da variância, arredondado ao inteiro mais próximo.
static func vary(dmg: int, rng: RandomNumberGenerator) -> int:
	return roundi(dmg * rng.randf_range(1.0 - SPREAD, 1.0 + SPREAD))


static func is_crit(rng: RandomNumberGenerator, chance := CRIT) -> bool:
	return rng.randf() < chance
